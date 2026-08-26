package imagestore

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// Cloudflare R2, which speaks the S3 API, reached through **minio-go** rather than aws-sdk-go-v2.
//
// Both were on the table and the deciding argument is the number of moving parts. What this file
// needs is three calls - put an object, delete an object, list a prefix - against one endpoint with
// one static key pair. minio-go is a single module that does exactly that. aws-sdk-go-v2's s3 client
// arrives with `config`, `credentials`, `smithy-go` and around a dozen internal modules whose job is
// resolving what we are hardcoding anyway: the region is "auto", the endpoint is written out below,
// and the credentials come from four environment variables rather than from a profile chain, an IMDS
// lookup or SSO. Paying for that machinery to switch it all off is the opposite of the trade.
//
// The cost of the choice: minio-go is written against MinIO's reading of S3, so anything exotic
// (presigned POST policies, object lock, S3 Select) would need checking against R2 rather than
// assumed. None of that is used here, and if it ever is, this file is the whole boundary.

const (
	// R2 does not have regions the way S3 does; "auto" is what Cloudflare's documentation says to
	// send, and the value only ever appears inside the SigV4 signature.
	r2Region = "auto"

	// what the object's own headers say. **The cache header is not decoration** - it is the same
	// `immutable, max-age=1y` staticFiles sets on the disk path, and it is safe for exactly the same
	// reason: a stored file's name is random, so a url is never reused (see randomName).
	r2ContentType  = "image/jpeg"
	r2CacheControl = "public, max-age=31536000, immutable"

	// A bound on one upload or delete, applied inside this file rather than left to the caller.
	// Without it a stalled connection to Cloudflare holds an http handler open for as long as the
	// TCP stack is willing to wait, and the shop owner who pressed "добавить фото" sees a spinner
	// with no end. 30s is far above two ~150 KB PUTs over any working link.
	r2OpTimeout = 30 * time.Second

	// the sweep's listing walks every uploaded file in the market, so it gets its own, longer bound
	r2ListTimeout = 2 * time.Minute
)

// R2Config is the four things needed to reach a bucket, and nothing else. Read from the environment
// by [R2ConfigFromEnv].
type R2Config struct {
	AccountID string
	AccessKey string
	SecretKey string
	Bucket    string
}

// the environment variables main.go decides on. Named after the product rather than after S3,
// because that is what the Cloudflare dashboard calls them when it hands them over.
const (
	EnvR2AccountID = "R2_ACCOUNT_ID"
	EnvR2AccessKey = "R2_ACCESS_KEY_ID"
	EnvR2SecretKey = "R2_SECRET_ACCESS_KEY"
	EnvR2Bucket    = "R2_BUCKET"
)

// R2ConfigFromEnv reads the four variables. The second return value is whether *any* of them was
// set, which is what main.go branches on: none set is a laptop and means the disk, and anything else
// is a deployment that meant to use R2.
//
// **A partial configuration is an error rather than a silent fall back to the disk.** Three keys out
// of four is somebody halfway through filling in a .env, and answering that by quietly writing
// photos onto the container's filesystem produces a server that works perfectly until it is
// restarted, at which point every photo uploaded since the last deploy is gone.
func R2ConfigFromEnv() (R2Config, bool, error) {
	cfg := R2Config{
		AccountID: strings.TrimSpace(os.Getenv(EnvR2AccountID)),
		AccessKey: strings.TrimSpace(os.Getenv(EnvR2AccessKey)),
		SecretKey: strings.TrimSpace(os.Getenv(EnvR2SecretKey)),
		Bucket:    strings.TrimSpace(os.Getenv(EnvR2Bucket)),
	}

	set := map[string]string{
		EnvR2AccountID: cfg.AccountID,
		EnvR2AccessKey: cfg.AccessKey,
		EnvR2SecretKey: cfg.SecretKey,
		EnvR2Bucket:    cfg.Bucket,
	}
	var missing []string
	any := false
	for _, name := range []string{EnvR2AccountID, EnvR2AccessKey, EnvR2SecretKey, EnvR2Bucket} {
		if set[name] == "" {
			missing = append(missing, name)
		} else {
			any = true
		}
	}
	if !any {
		return R2Config{}, false, nil
	}
	if len(missing) > 0 {
		return R2Config{}, true, fmt.Errorf(
			"imagestore: R2 is partly configured - %s %s missing",
			strings.Join(missing, ", "), plural(len(missing), "is", "are"))
	}
	return cfg, true, nil
}

func plural(n int, one, many string) string {
	if n == 1 {
		return one
	}
	return many
}

// Endpoint is the S3 host for this account, without a scheme - which is the shape minio.New wants,
// with https chosen separately by Options.Secure.
//
// Written out here rather than taken as a fifth setting: it is derived from the account id by a rule
// Cloudflare documents, so a setting for it would be a fifth thing that can be wrong and a fifth
// thing to keep in step. This is also the one piece of address assembly that is worth a test, since
// getting it wrong produces a DNS failure at the first upload and nowhere earlier.
func (c R2Config) Endpoint() string {
	return c.AccountID + ".r2.cloudflarestorage.com"
}

// R2 is [Storage] backed by a Cloudflare R2 bucket.
//
// **The object keys are byte-identical to the paths [Disk] writes** - "uploads/3f/3f9c.jpg", no
// bucket-side prefix of its own. That is what makes products.image_path portable: a dump taken from
// production restores onto a laptop and every row still points at something the disk store can find,
// and a move in the other direction needs no rewriting either.
type R2 struct {
	client *minio.Client
	bucket string
	host   string
}

var _ Storage = (*R2)(nil)

// NewR2 builds the client. It performs no network call - minio.New only assembles credentials and an
// endpoint - so a wrong key or an unreachable bucket is discovered at the first upload rather than
// at boot. That is a deliberate acceptance rather than an oversight: a HeadBucket at startup would
// make the api refuse to boot during a Cloudflare incident, when everything except photo upload
// would otherwise still work.
func NewR2(cfg R2Config) (*R2, error) {
	client, err := minio.New(cfg.Endpoint(), &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure: true,
		Region: r2Region,
		// R2 addresses a bucket as a path segment under the account host. minio-go's automatic mode
		// reaches the same conclusion for an unknown endpoint, but "the SDK guessed right" is not
		// the kind of thing to leave implicit in the one code path that cannot be tested offline.
		BucketLookup: minio.BucketLookupPath,
	})
	if err != nil {
		return nil, fmt.Errorf("imagestore: cannot build the R2 client: %w", err)
	}
	return &R2{client: client, bucket: cfg.Bucket, host: cfg.Endpoint()}, nil
}

func (r *R2) Describe() string { return "Cloudflare R2 bucket " + r.bucket + " at " + r.host }

// Save uploads both copies and returns the master's relative path.
//
// Same ordering as [Disk.Save] and for the same reason: the thumbnail goes up first, so there is
// never a master reachable by a reader whose thumbnail has not landed yet.
func (r *R2) Save(ctx context.Context, photo Photo) (string, error) {
	master, thumb, err := newPaths()
	if err != nil {
		return "", err
	}

	ctx, cancel := context.WithTimeout(ctx, r2OpTimeout)
	defer cancel()

	if err := r.put(ctx, thumb, photo.Thumb); err != nil {
		return "", err
	}
	if err := r.put(ctx, master, photo.Master); err != nil {
		// nothing learned the thumbnail's name, so it would sit in the bucket forever
		_ = r.client.RemoveObject(ctx, r.bucket, thumb, minio.RemoveObjectOptions{})
		return "", err
	}
	return master, nil
}

func (r *R2) Remove(ctx context.Context, rel string) error {
	if !IsUpload(rel) {
		return fmt.Errorf("%w: %q", ErrOutsideUploads, rel)
	}
	ctx, cancel := context.WithTimeout(ctx, r2OpTimeout)
	defer cancel()

	// the mirror of Save, and the same note applies: either half failing leaves a file for the sweep
	if err := r.delete(ctx, ThumbPath(rel)); err != nil {
		return err
	}
	return r.delete(ctx, rel)
}

func (r *R2) RemoveFile(ctx context.Context, rel string) error {
	if !IsUpload(rel) {
		return fmt.Errorf("%w: %q", ErrOutsideUploads, rel)
	}
	ctx, cancel := context.WithTimeout(ctx, r2OpTimeout)
	defer cancel()

	return r.delete(ctx, rel)
}

// List walks every object under uploads/. The prefix is not a filter applied afterwards - it is sent
// to the bucket, so the curated catalogue (which lives in the same bucket, under universal/ and
// plumbing/) is never even enumerated, let alone considered for deletion.
func (r *R2) List(ctx context.Context) ([]Object, error) {
	ctx, cancel := context.WithTimeout(ctx, r2ListTimeout)
	defer cancel()

	var out []Object
	// ListObjects returns a channel and fills it from a goroutine, one page of results at a time.
	// Ranging to the end is what closes it; bailing out early would leak that goroutine, which is
	// why an error below returns only after the loop, not from inside it.
	var listErr error
	for obj := range r.client.ListObjects(ctx, r.bucket, minio.ListObjectsOptions{
		Prefix:    UploadDir + "/",
		Recursive: true,
	}) {
		if obj.Err != nil {
			listErr = obj.Err
			continue
		}
		out = append(out, Object{Path: obj.Key, Size: obj.Size, Modified: obj.LastModified})
	}
	if listErr != nil {
		return nil, fmt.Errorf("imagestore: listing the R2 bucket: %w", listErr)
	}
	return out, nil
}

func (r *R2) put(ctx context.Context, key string, content []byte) error {
	_, err := r.client.PutObject(ctx, r.bucket, key,
		bytes.NewReader(content), int64(len(content)),
		minio.PutObjectOptions{ContentType: r2ContentType, CacheControl: r2CacheControl})
	if err != nil {
		return fmt.Errorf("imagestore: uploading %q to R2: %w", key, err)
	}
	return nil
}

// deleting what is already gone is a success, the same contract [Disk] keeps. S3 answers a DELETE of
// a missing key with 204 anyway, so the NoSuchKey branch is for a bucket that behaves differently
// rather than for R2 as it stands.
func (r *R2) delete(ctx context.Context, key string) error {
	err := r.client.RemoveObject(ctx, r.bucket, key, minio.RemoveObjectOptions{})
	if err == nil {
		return nil
	}
	var response minio.ErrorResponse
	if errors.As(err, &response) && response.Code == "NoSuchKey" {
		return nil
	}
	return fmt.Errorf("imagestore: removing %q from R2: %w", key, err)
}
