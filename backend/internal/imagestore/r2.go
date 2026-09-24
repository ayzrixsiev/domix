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

// Cloudflare R2, which speaks the S3 API, through **minio-go rather than aws-sdk-go-v2**: this file
// needs three calls against one endpoint with one static key pair, and the aws sdk's dozen modules
// exist to resolve a region, an endpoint and a credential chain we are all hardcoding anyway.
//
// the cost: minio-go follows MinIO's reading of S3, so anything exotic would need checking against
// R2 rather than assumed. none of it is used here, and this file is the whole boundary.

const (
	// R2 has no regions; "auto" only ever appears inside the SigV4 signature
	r2Region = "auto"

	// **the cache header is not decoration** - the same immutable year staticFiles sets on the disk
	// path, safe for the same reason: a stored file's name is random, so a url is never reused
	r2ContentType  = "image/jpeg"
	r2CacheControl = "public, max-age=31536000, immutable"

	// without it a stalled connection to Cloudflare holds an http handler open for as long as the
	// TCP stack will wait, and the owner who pressed "добавить фото" sees a spinner with no end
	r2OpTimeout = 30 * time.Second

	// the sweep's listing walks every uploaded file in the market, so it gets a longer bound
	r2ListTimeout = 2 * time.Minute
)

// the four things needed to reach a bucket, and nothing else
type R2Config struct {
	AccountID string
	AccessKey string
	SecretKey string
	Bucket    string
}

// named after the product rather than after S3 - what the Cloudflare dashboard calls them
const (
	EnvR2AccountID = "R2_ACCOUNT_ID"
	EnvR2AccessKey = "R2_ACCESS_KEY_ID"
	EnvR2SecretKey = "R2_SECRET_ACCESS_KEY"
	EnvR2Bucket    = "R2_BUCKET"
)

// the second return is whether *any* of the four was set: none means a laptop and the disk,
// anything else is a deployment that meant to use R2.
//
// **a partial configuration is an error rather than a silent fall back to the disk**: writing photos
// onto the container's filesystem gives a server that works perfectly until it is restarted, at
// which point every photo uploaded since the last deploy is gone.
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

// the S3 host for this account, without a scheme. derived rather than taken as a fifth setting,
// which would be a fifth thing that can be wrong - and getting it wrong fails at the first upload
// and nowhere earlier, which is why it has a test.
func (c R2Config) Endpoint() string {
	return c.AccountID + ".r2.cloudflarestorage.com"
}

// **the object keys are byte-identical to the paths [Disk] writes**, with no bucket-side prefix,
// which is what makes products.image_path portable: a production dump restores onto a laptop and
// every row still points at something the disk store can find.
type R2 struct {
	client *minio.Client
	bucket string
	host   string
}

var _ Storage = (*R2)(nil)

// no network call here, so a wrong key is discovered at the first upload rather than at boot -
// deliberately: a HeadBucket at startup would refuse to boot the whole api during a Cloudflare
// incident, when everything except photo upload would still work.
func NewR2(cfg R2Config) (*R2, error) {
	client, err := minio.New(cfg.Endpoint(), &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure: true,
		Region: r2Region,
		// R2 addresses a bucket as a path segment. minio-go's automatic mode guesses the same, and
		// "the SDK guessed right" is not what to rely on in the one path that cannot be tested offline.
		BucketLookup: minio.BucketLookupPath,
	})
	if err != nil {
		return nil, fmt.Errorf("imagestore: cannot build the R2 client: %w", err)
	}
	return &R2{client: client, bucket: cfg.Bucket, host: cfg.Endpoint()}, nil
}

func (r *R2) Describe() string { return "Cloudflare R2 bucket " + r.bucket + " at " + r.host }

// the same ordering as [Disk.Save]: the thumbnail goes up first, so no reader can reach a master
// whose thumbnail has not landed
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

	// the mirror of Save: either half failing leaves a file for the sweep
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

// every object under uploads/. **the prefix is sent to the bucket, not filtered afterwards**, so the
// curated catalogue - same bucket, other prefixes - is never enumerated, let alone deleted.
func (r *R2) List(ctx context.Context) ([]Object, error) {
	ctx, cancel := context.WithTimeout(ctx, r2ListTimeout)
	defer cancel()

	var out []Object
	// ListObjects fills a channel from a goroutine, and ranging to the end is what closes it - so an
	// error returns after the loop rather than from inside it
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

// deleting what is already gone is a success, the same contract [Disk] keeps
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
