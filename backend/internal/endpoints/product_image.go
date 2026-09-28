package endpoints

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/imagestore"
)

// the product photo endpoints:
//
//	POST   /api/products/{id}/image  - owner uploads or replaces one photo (multipart, field "image")
//	DELETE /api/products/{id}/image  - owner removes it
//
// **an owner may photograph anything we have not photographed, and nothing we have** - their own
// products always, and обои slots, which name a *kind* of wallpaper and have nothing to shoot. the
// answer comes from the template rather than the shop's category, so photographing a catalogue
// locks its rows by itself: see templateFlags.
//
// a separate endpoint rather than a field on PUT: a photo arrives as multipart bytes while the rest
// of the form is json, and it saves the instant it is picked rather than on "сохранить".
func (p *Products) RouteImage(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		auth.RequireAuth(p.JWTSecret, p.Queries, p.UploadImage)(w, r)
	case http.MethodDelete:
		auth.RequireAuth(p.JWTSecret, p.Queries, p.RemoveImage)(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// one field, one file: there is exactly one photo per product
const imageFormField = "image"

// UploadImage stores one photo and points the row at it. **the ordering is the design**: write the
// new file under a name nothing refers to, point the row at it, then unlink the old one. every
// failure leaves the database true, where unlinking first leaves a row naming a file that is gone.
func (p *Products) UploadImage(w http.ResponseWriter, r *http.Request) {
	existing, ok := p.authorizeProductAccess(w, r)
	if !ok {
		return
	}

	// before the limiter and before a byte is read: refusing 6 MiB after receiving it spends the
	// bandwidth this answer exists to save
	if _, _, photoEditable := templateFlags(existing.TemplateKey); !photoEditable {
		writeAPIError(w, http.StatusForbidden, "template_photo",
			"the catalogue photo of a template product cannot be replaced")
		return
	}

	if !p.allowUpload(w, r) {
		return
	}

	raw, ok := readUploadedImage(w, r)
	if !ok {
		return
	}

	// one decode, two files: a 1000px master and a 400px thumbnail, carried as one value so no path
	// can store a master whose thumbnail is missing
	normalized, err := imagestore.Normalize(raw)
	if err != nil {
		writeImageError(w, err)
		return
	}

	stored, err := p.Images.Save(r.Context(), normalized)
	if err != nil {
		log.Printf("CRITICAL: could not store a photo for product %d: %v", existing.ID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to save the photo")
		return
	}

	updated, ok := p.pointProductAt(w, r, existing.ID, pgtype.Text{String: stored, Valid: true})
	if !ok {
		// the row still names the old photo, so this one is referenced by nothing
		if err := p.Images.Remove(r.Context(), stored); err != nil {
			log.Printf("WARNING: orphaned upload %q could not be removed: %v", stored, err)
		}
		return
	}

	p.forgetPreviousUpload(r, existing.ImagePath)
	p.writeProductResponse(w, http.StatusOK, updated)
}

// RemoveImage takes the owner's photo off a product. **on a seeded row it restores the catalogue
// shot rather than clearing the column** - that file is still on disk and shared by every shop of
// the category.
//
// deliberately not gated by the rule UploadImage enforces: removal can only move a row *towards* the
// catalogue, and gating it would strand an owner who uploaded before we photographed that category.
func (p *Products) RemoveImage(w http.ResponseWriter, r *http.Request) {
	existing, ok := p.authorizeProductAccess(w, r)
	if !ok {
		return
	}

	// "" for the owner's own row, and for a template row whose catalogue has no photo
	restored := pgtype.Text{}
	if existing.TemplateKey.Valid {
		if fallback := catalog.TemplateImage(existing.TemplateKey.String); fallback != "" {
			restored = pgtype.Text{String: fallback, Valid: true}
		}
	}

	updated, ok := p.pointProductAt(w, r, existing.ID, restored)
	if !ok {
		return
	}

	p.forgetPreviousUpload(r, existing.ImagePath)
	p.writeProductResponse(w, http.StatusOK, updated)
}

// the shared tail of both handlers: write the column, or report why not.
func (p *Products) pointProductAt(w http.ResponseWriter, r *http.Request, productID int64, path pgtype.Text) (db.SetProductImageRow, bool) {
	// a fresh timeout: authorizeProductAccess's cancel() already fired when it returned
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	updated, err := p.Queries.SetProductImage(ctx, db.SetProductImageParams{ID: productID, ImagePath: path})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// it existed when we read it to authorize, so it was deleted in between
			writeAPIError(w, http.StatusNotFound, "product_not_found", "product not found")
			return db.SetProductImageRow{}, false
		}
		log.Printf("CRITICAL: could not set the photo of product %d: %v", productID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to save the photo")
		return db.SetProductImageRow{}, false
	}
	return updated, true
}

// unlink both files of the photo the row used to name. **IsUpload is the line that protects the
// catalogue**: image_path holds curated shots too, and deleting one because a single owner replaced
// their photo would blank that tile in every other shop of the category.
func (p *Products) forgetPreviousUpload(r *http.Request, previous pgtype.Text) {
	if !previous.Valid || !imagestore.IsUpload(previous.String) {
		return
	}
	if err := p.Images.Remove(r.Context(), previous.String); err != nil {
		log.Printf("WARNING: could not remove the replaced photo %q: %v", previous.String, err)
	}
}

// reads the uploaded file out of the multipart body. **MaxBytesReader is what makes the bound
// real**: ParseMultipartForm's own argument only decides how much it holds in memory before
// spilling to a temp file, so without this a request could stream gigabytes onto disk first.
func readUploadedImage(w http.ResponseWriter, r *http.Request) ([]byte, bool) {
	r.Body = http.MaxBytesReader(w, r.Body, imagestore.MaxUploadBytes)

	file, _, err := r.FormFile(imageFormField)
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			writeAPIError(w, http.StatusRequestEntityTooLarge, "image_too_large",
				fmt.Sprintf("the photo may not be larger than %d MB", imagestore.MaxUploadBytes>>20))
			return nil, false
		}
		if errors.Is(err, http.ErrMissingFile) {
			writeAPIError(w, http.StatusBadRequest, "missing_image", "no photo was attached")
			return nil, false
		}
		writeAPIError(w, http.StatusBadRequest, "invalid_upload", "the upload could not be read")
		return nil, false
	}
	defer file.Close()

	raw, err := io.ReadAll(file)
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			writeAPIError(w, http.StatusRequestEntityTooLarge, "image_too_large",
				fmt.Sprintf("the photo may not be larger than %d MB", imagestore.MaxUploadBytes>>20))
			return nil, false
		}
		writeAPIError(w, http.StatusBadRequest, "invalid_upload", "the upload could not be read")
		return nil, false
	}

	return raw, true
}

// Normalize's sentinels as codes the app localizes. anything unrecognised is a 400, not a 500:
// Normalize only fails on what it was given.
func writeImageError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, imagestore.ErrTooSmall):
		writeAPIError(w, http.StatusBadRequest, "image_too_small", "the photo is too small")
	case errors.Is(err, imagestore.ErrTooLarge):
		writeAPIError(w, http.StatusBadRequest, "image_too_large", "the photo has too many pixels")
	case errors.Is(err, imagestore.ErrUnsupportedFormat), errors.Is(err, imagestore.ErrBroken):
		writeAPIError(w, http.StatusBadRequest, "invalid_image", "that file is not a jpeg or png photo")
	default:
		log.Printf("CRITICAL: unexpected failure normalizing an upload: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to process the photo")
	}
}

// the per-account ceiling on uploads, which the per-IP limiter cannot express: a shop's staff share
// one office address, and one phone changes address between cells. one request here means decoding
// and re-encoding an image, so it is a far more expensive call than a read.
func (p *Products) allowUpload(w http.ResponseWriter, r *http.Request) bool {
	if p.Uploads == nil {
		return true // no limiter configured: the tests, which call the handler directly
	}
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		return true // unreachable behind RequireAuth, and failing open here changes nothing
	}

	if !p.Uploads.Allow("user:" + strconv.FormatInt(userID, 10)) {
		writeAPIError(w, http.StatusTooManyRequests, "too_many_uploads",
			"too many photos at once, wait a moment")
		return false
	}
	return true
}

// one response shape for a product, whichever statement produced it
func (p *Products) writeProductResponse(w http.ResponseWriter, status int, row db.SetProductImageRow) {
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(productResponse(p.URLs, db.GetProductRow(row)))
}

