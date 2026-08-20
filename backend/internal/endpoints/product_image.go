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
// **An owner may photograph anything we have not photographed, and nothing we have.** That means
// their own products always, обои slots (a slot names a *kind* of wallpaper, so there is nothing to
// shoot) and древесные материалы (never shot) - and it means the универсальный and сантехника
// catalogues are ours. The rule is asked of the template rather than of the shop's category, so it
// is `templateFlags`'s third return value; that function's comment has why.
//
// The rule used to be the opposite - every row, template ones included - on the reasoning that a
// photograph is not one of the three things (key, name, unit) that make two baskets comparable, and
// that a shop stocking a different brand of the same seeded item describes itself more honestly with
// its own picture. What that reasoning missed is what the shared catalogue *is*: one file on disk,
// shot and chosen by us, that every shop of the category draws. An owner replacing it puts a photo
// of a different object on a row the index insists is the same product as the one across the road,
// and it is the customer comparing two shops who is misled. Moderation was the answer offered, and
// moderating a hundred rows in every shop by hand is not an answer.
//
// A separate endpoint rather than a field on PUT /api/products/{id}, for two reasons that both point
// the same way: a photo arrives as multipart bytes and everything else on that form is json, and a
// photo is saved the instant it is picked while the rest of the form is saved when the owner presses
// "сохранить". Folding them together would mean either making the whole product form multipart or
// base64-ing a megabyte of jpeg through a json field.
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

// the multipart field the photo arrives in. one field, one file - there is exactly one photo per
// product, and a gallery would be a different feature with a different table.
const imageFormField = "image"

// UploadImage stores one photo against one product and points the row at it.
//
// The ordering is the whole design, and it is chosen so that every way this can fail leaves the
// database true:
//
//  1. write the new file, under a name nothing yet refers to;
//  2. point the row at it;
//  3. unlink whatever the row pointed at before.
//
// Fail at 1 and nothing changed. Fail at 2 and there is an unused file on disk, which costs a
// hundred kilobytes and shows up nowhere. The opposite order - unlink first, then write - has a
// window where the row names a file that is gone, which is a broken tile in every grid the product
// appears in and is not recoverable by retrying.
func (p *Products) UploadImage(w http.ResponseWriter, r *http.Request) {
	existing, ok := p.authorizeProductAccess(w, r)
	if !ok {
		return
	}

	// checked before the rate limiter and before a single byte is read: refusing a six-megabyte
	// upload after receiving it would spend the bandwidth this answer exists to save.
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

	normalized, err := imagestore.Normalize(raw)
	if err != nil {
		writeImageError(w, err)
		return
	}

	stored, err := p.Images.Save(normalized)
	if err != nil {
		log.Printf("CRITICAL: could not store a photo for product %d: %v", existing.ID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to save the photo")
		return
	}

	updated, ok := p.pointProductAt(w, r, existing.ID, pgtype.Text{String: stored, Valid: true})
	if !ok {
		// the row still names the old photo, so this one is referenced by nothing
		if err := p.Images.Remove(stored); err != nil {
			log.Printf("WARNING: orphaned upload %q could not be removed: %v", stored, err)
		}
		return
	}

	p.forgetPreviousUpload(existing.ImagePath)
	writeProductResponse(w, http.StatusOK, updated)
}

// RemoveImage takes the owner's photo off a product.
//
// **On a seeded row this restores the catalogue photo rather than clearing the column.** The shot
// under photos/<category>/ is what that row arrived with and is still on disk - it is shared by
// every shop of the category - so putting the path back is both correct and free, where clearing it
// would leave the owner with no way to get back to the state they started in.
//
// **Deliberately not gated by the rule UploadImage enforces**, even though the two are the same
// question one step apart. Removal can only ever move a row *towards* the catalogue, so refusing it
// protects nothing - and the case it would break is real: an owner photographs a wood row today, the
// wood catalogue is shot next month, and their upload is now the one thing on the row that the rule
// says should not be there. With removal open they can put the catalogue's shot back; gated, they
// are stuck with their own picture forever.
func (p *Products) RemoveImage(w http.ResponseWriter, r *http.Request) {
	existing, ok := p.authorizeProductAccess(w, r)
	if !ok {
		return
	}

	// "" for a product of the owner's own, and for a template row whose catalogue has no photo -
	// every обои slot, and the five product categories nothing has been photographed for yet
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

	p.forgetPreviousUpload(existing.ImagePath)
	writeProductResponse(w, http.StatusOK, updated)
}

// the shared tail of both handlers: write the column, or report why not.
func (p *Products) pointProductAt(w http.ResponseWriter, r *http.Request, productID int64, path pgtype.Text) (db.SetProductImageRow, bool) {
	// a fresh timeout rather than the one authorizeProductAccess used, whose cancel() has already
	// fired - the same reason Update takes one
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

// unlink the photo the row used to name, now that nothing points at it.
//
// **Guarded by IsUpload, which is the line that protects the catalogue.** products.image_path holds
// curated shots as well as uploads, and those are shared by every shop seeded from the same
// template - deleting one because a single owner replaced their photo would blank the tile in every
// other shop of that category. A failure here is logged and swallowed: the row is already correct,
// and the cost of the leak is one file.
func (p *Products) forgetPreviousUpload(previous pgtype.Text) {
	if !previous.Valid || !imagestore.IsUpload(previous.String) {
		return
	}
	if err := p.Images.Remove(previous.String); err != nil {
		log.Printf("WARNING: could not remove the replaced photo %q: %v", previous.String, err)
	}
}

// reads the uploaded file out of the multipart body, bounded.
//
// **MaxBytesReader is what makes the bound real.** ParseMultipartForm's own argument only decides
// how much it keeps in memory before spilling to a temp file, so without this a request could stream
// gigabytes onto the server's disk and be refused afterwards, having already cost the thing the
// limit exists to protect.
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

// turns Normalize's sentinel errors into codes the app localizes. anything unrecognised is a 400
// rather than a 500: Normalize only fails on what it was given.
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

// the per-account ceiling on uploads.
//
// The general limiter in front of every route is per-IP at 20 requests a second, which is the right
// shape for reads and no protection at all for an endpoint where one request means decoding and
// re-encoding an image. This one is asked per *account*, which the IP limiter cannot do: a shop's
// staff on one office wifi share an address, and one phone changes address between cells.
//
// One a second sustained with a burst of twenty is deliberately far above the workflow it has to
// allow - an owner photographing a hundred products still picks each one by hand - and far below
// what a script would want.
func (p *Products) allowUpload(w http.ResponseWriter, r *http.Request) bool {
	if p.Uploads == nil {
		return true // no limiter configured: the endpoint tests, which exercise the handler directly
	}
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		return true // RequireAuth ran before this; unreachable, and failing open here changes nothing
	}

	if !p.Uploads.Allow("user:" + strconv.FormatInt(userID, 10)) {
		writeAPIError(w, http.StatusTooManyRequests, "too_many_uploads",
			"too many photos at once, wait a moment")
		return false
	}
	return true
}

// the SetProductImage row shares every field the other four product statements return, so it maps
// through the same shape - one response type for a product, whichever statement produced it.
func writeProductResponse(w http.ResponseWriter, status int, row db.SetProductImageRow) {
	isTemplate, nameEditable, photoEditable := templateFlags(row.TemplateKey)
	imageURL, ownImage := productImage(row.ImagePath)

	w.WriteHeader(status)
	json.NewEncoder(w).Encode(ProductResponse{
		ID:            row.ID,
		ShopID:        row.ShopID,
		Name:          row.Name,
		Category:      row.Category,
		Unit:          row.Unit,
		Price:         nullableInt64(row.Price),
		Availability:  row.Availability,
		IsTemplate:    isTemplate,
		NameEditable:  nameEditable,
		ImageURL:      imageURL,
		OwnImage:      ownImage,
		PhotoEditable: photoEditable,
	})
}
