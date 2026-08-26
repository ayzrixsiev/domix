package imagestore

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"
)

const (
	filePerm = 0o644
	dirPerm  = 0o755
)

// Disk writes into `root`/uploads, where root is the same directory the api serves
// /static/products/ from (PRODUCT_IMAGES_DIR).
//
// **It is not the legacy implementation and does not go away when R2 arrives.** It is what runs on
// the founder's laptop, in `go test ./...`, and on any machine with no credentials and no network -
// which is the argument for [Storage] being an interface at all. An abstraction with one real
// implementation and one stub is architecture; this one has two implementations that both run every
// day.
type Disk struct {
	root string
}

// compile-time proof that this satisfies the interface. cheaper than finding out from main.go.
var _ Storage = (*Disk)(nil)

// NewDisk makes sure the uploads directory exists and hands back a store writing into it.
//
// Creating it at startup rather than lazily on the first upload is deliberate: a directory the
// process cannot create is a misconfigured deployment, and finding that out when the first shop
// owner presses "добавить фото" means finding out from them.
func NewDisk(root string) (*Disk, error) {
	dir := filepath.Join(root, UploadDir)
	if err := os.MkdirAll(dir, dirPerm); err != nil {
		return nil, fmt.Errorf("imagestore: cannot create %q: %w", dir, err)
	}
	return &Disk{root: root}, nil
}

// Dir is the path uploads are written under. For the startup log and for tests.
func (d *Disk) Dir() string { return filepath.Join(d.root, UploadDir) }

func (d *Disk) Describe() string { return "local disk at " + d.Dir() }

// Save writes both copies and returns the master's relative path.
//
// **The master goes down last.** Both files are written under names nothing yet refers to, so the
// order cannot leave a row pointing at a missing file - but a thumbnail written after its master
// leaves a window where a *concurrent* reader of the row (there is none today; there will be when a
// second process serves these) could ask for a thumbnail that is not there yet. Writing the small
// one first costs nothing and closes it.
func (d *Disk) Save(_ context.Context, photo Photo) (string, error) {
	master, thumb, err := newPaths()
	if err != nil {
		return "", err
	}

	if err := d.write(thumb, photo.Thumb); err != nil {
		return "", err
	}
	if err := d.write(master, photo.Master); err != nil {
		// the thumbnail is referenced by nothing - the caller never learned its name - so it would
		// sit on disk forever. cleaned up here rather than left to the sweep, which is for files
		// whose row went away rather than for ones we know are dead the moment we write them.
		_ = d.removeAt(thumb)
		return "", err
	}
	return master, nil
}

func (d *Disk) Remove(ctx context.Context, rel string) error {
	if !IsUpload(rel) {
		return fmt.Errorf("%w: %q", ErrOutsideUploads, rel)
	}
	// the mirror of Save: thumbnail first, master second. Either half failing leaves a file the
	// admin panel's sweep will collect, so what the order buys is only that the two operations read
	// the same way round in both directions.
	if err := d.removeAt(ThumbPath(rel)); err != nil {
		return err
	}
	return d.RemoveFile(ctx, rel)
}

func (d *Disk) RemoveFile(_ context.Context, rel string) error {
	if !IsUpload(rel) {
		return fmt.Errorf("%w: %q", ErrOutsideUploads, rel)
	}
	return d.removeAt(rel)
}

// List walks `root`/uploads. Returns relative, forward-slashed paths, so what comes out is directly
// comparable with what is in products.image_path on either backend.
func (d *Disk) List(_ context.Context) ([]Object, error) {
	dir := d.Dir()
	var out []Object

	err := filepath.WalkDir(dir, func(full string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		// the half-written temp files CreateTemp leaves behind if the process dies mid-save. they
		// are not photos and nothing will ever reference them; skipping keeps them out of a report
		// that is about files whose product is gone.
		if strings.HasPrefix(entry.Name(), ".upload-") {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			// vanished between the walk and the stat - somebody replaced a photo while we were
			// listing, which is exactly the race the sweep's one-hour floor exists for
			if errors.Is(err, fs.ErrNotExist) {
				return nil
			}
			return err
		}
		rel, err := filepath.Rel(d.root, full)
		if err != nil {
			return err
		}
		out = append(out, Object{
			Path:     filepath.ToSlash(rel),
			Size:     info.Size(),
			Modified: info.ModTime(),
		})
		return nil
	})
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return nil, fmt.Errorf("imagestore: listing %q: %w", dir, err)
	}
	return out, nil
}

// write puts one file down atomically: a temp file in the *same* directory, then a rename. Rename is
// atomic within one filesystem, so the static handler either does not see the path at all or sees a
// complete file - never the half of it that had been flushed when the process was killed.
func (d *Disk) write(rel string, content []byte) error {
	full := filepath.Join(d.root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), dirPerm); err != nil {
		return fmt.Errorf("imagestore: cannot create %q: %w", filepath.Dir(full), err)
	}

	tmp, err := os.CreateTemp(filepath.Dir(full), ".upload-*")
	if err != nil {
		return fmt.Errorf("imagestore: cannot create a temporary file: %w", err)
	}
	tmpName := tmp.Name()

	if _, err := tmp.Write(content); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return fmt.Errorf("imagestore: writing %q: %w", tmpName, err)
	}
	if err := tmp.Chmod(filePerm); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return fmt.Errorf("imagestore: chmod %q: %w", tmpName, err)
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return fmt.Errorf("imagestore: closing %q: %w", tmpName, err)
	}
	if err := os.Rename(tmpName, full); err != nil {
		os.Remove(tmpName)
		return fmt.Errorf("imagestore: renaming into %q: %w", full, err)
	}
	return nil
}

// unlink one path that has already been checked. A file that is not there is a success.
func (d *Disk) removeAt(rel string) error {
	err := os.Remove(filepath.Join(d.root, filepath.FromSlash(path.Clean(rel))))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("imagestore: removing %q: %w", rel, err)
	}
	return nil
}
