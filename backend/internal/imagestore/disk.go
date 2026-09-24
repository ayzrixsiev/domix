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

// Disk writes into `root`/shops/uploads, under the same images root the api serves /images/ from.
// **not the legacy implementation**: it is what runs on the laptop and in `go test ./...`, which is
// the argument for [Storage] being an interface at all.
type Disk struct {
	root string
}

// compile-time proof that this satisfies the interface
var _ Storage = (*Disk)(nil)

// creates the uploads directory at startup rather than on the first upload: a directory the process
// cannot write is a misconfigured deployment, and the first shop owner should not be the one to find
// that out
func NewDisk(root string) (*Disk, error) {
	dir := filepath.Join(root, UploadDir)
	if err := os.MkdirAll(dir, dirPerm); err != nil {
		return nil, fmt.Errorf("imagestore: cannot create %q: %w", dir, err)
	}
	return &Disk{root: root}, nil
}

// where uploads are written, for the startup log and for tests
func (d *Disk) Dir() string { return filepath.Join(d.root, UploadDir) }

func (d *Disk) Describe() string { return "local disk at " + d.Dir() }

// writes both copies and returns the master's relative path. **the master goes down last**, so no
// reader can ever find a master whose thumbnail has not landed yet.
func (d *Disk) Save(_ context.Context, photo Photo) (string, error) {
	master, thumb, err := newPaths()
	if err != nil {
		return "", err
	}

	if err := d.write(thumb, photo.Thumb); err != nil {
		return "", err
	}
	if err := d.write(master, photo.Master); err != nil {
		// the caller never learned the thumbnail's name, so nothing else would ever collect it
		_ = d.removeAt(thumb)
		return "", err
	}
	return master, nil
}

func (d *Disk) Remove(ctx context.Context, rel string) error {
	if !IsUpload(rel) {
		return fmt.Errorf("%w: %q", ErrOutsideUploads, rel)
	}
	// the mirror of Save. either half failing leaves a file the admin panel's sweep collects.
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

// walks `root`/uploads, returning relative forward-slashed paths - directly comparable with
// products.image_path on either backend
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
		// half-written temp files from a process that died mid-save: not photos, and not what a
		// report about files whose product is gone is asking about
		if strings.HasPrefix(entry.Name(), ".upload-") {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			// vanished between the walk and the stat - the race the sweep's one-hour floor exists for
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

// one file down atomically: a temp file in the *same* directory, then a rename. the static handler
// either does not see the path at all or sees a complete file, never a half-flushed one.
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

// unlink one already-checked path. a file that is not there is a success.
func (d *Disk) removeAt(rel string) error {
	err := os.Remove(filepath.Join(d.root, filepath.FromSlash(path.Clean(rel))))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("imagestore: removing %q: %w", rel, err)
	}
	return nil
}
