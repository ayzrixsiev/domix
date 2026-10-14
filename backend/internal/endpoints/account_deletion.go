package endpoints

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/imagestore"
	"domix/backend/internal/verify"
)

// the /delete-account page's api - the same six-digit code the login uses, typed on a web page
// instead of in the app. Google Play requires deletion to be reachable without installing the app.
//
//	POST /api/account-deletion/request-code  {phone}        -> a code goes to that number
//	POST /api/account-deletion/confirm       {phone, code}  -> the account, its shops and products
//
// **the answer is identical whether or not an account exists, and a code is only sent when one does.**
// anything else turns a public page into a way to ask whether a number is registered with Domix, and
// into a way to make us pay for codes aimed at numbers that never signed up. the pending entry is
// minted either way, so the cooldown cannot be used to tell the two apart.
type AccountDeletion struct {
	Queries *db.Queries
	Codes   *auth.CodeManager
	Sender  verify.Sender

	// where the owner's photos live, so deleting the account deletes them too - see eraseAccount
	Images imagestore.Storage
}

// POST /api/account-deletion/request-code
func (d *AccountDeletion) RequestCode(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Phone string `json:"phone"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	phone, ok := auth.CanonicalPhone(req.Phone)
	if !ok {
		writeAPIError(w, http.StatusBadRequest, "invalid_phone", "that is not an uzbek phone number")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	registered, err := d.accountExists(ctx, phone)
	if err != nil {
		log.Printf("CRITICAL: could not check whether %s has an account: %v", auth.MaskPhone(phone), err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not start the deletion")
		return
	}

	// minted before the branch, so the cooldown and the budget behave identically either way
	code, wait, err := d.Codes.Issue(auth.Pending{Purpose: auth.CodeDeletion, Phone: phone})
	if err != nil {
		writeIssueError(w, err, wait)
		return
	}

	if registered && d.Codes.NeedsDelivery(phone) {
		sendCtx, cancelSend := context.WithTimeout(context.WithoutCancel(r.Context()), codeSendTimeout)
		defer cancelSend()

		if err := d.Sender.Send(sendCtx, phone, code); err != nil {
			d.Codes.Drop(phone)
			log.Printf("WARNING: could not deliver a deletion code to %s: %v", auth.MaskPhone(phone), err)
			writeAPIError(w, http.StatusBadGateway, "code_not_sent", "could not send the code, try again")
			return
		}
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"sent":         true,
		"phone":        phone,
		"expires_in":   int(auth.CodeTTL.Seconds()),
		"resend_after": int(auth.ResendCooldown.Seconds()),
	})
}

// POST /api/account-deletion/confirm - the code was right, so the number is theirs.
func (d *AccountDeletion) Confirm(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Phone string `json:"phone"`
		Code  string `json:"code"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	phone, ok := auth.CanonicalPhone(req.Phone)
	if !ok {
		writeAPIError(w, http.StatusBadRequest, "invalid_phone", "that is not an uzbek phone number")
		return
	}

	// nothing is read or written until the code is right, and CodeDeletion is what stops a login
	// code for this number being spent here
	if _, err := d.Codes.Verify(auth.CodeDeletion, phone, strings.TrimSpace(req.Code)); err != nil {
		writeCodeError(w, err)
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	user, err := d.Queries.GetUserByPhone(ctx, phone)
	if err != nil {
		// nothing to delete, and saying so is safe here and nowhere else: they have just proved they
		// own the number, so it tells them nothing they could not already find out
		if errors.Is(err, pgx.ErrNoRows) {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
			return
		}
		log.Printf("CRITICAL: deletion lookup failed for %s: %v", auth.MaskPhone(phone), err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not delete the account")
		return
	}

	if err := eraseAccount(ctx, d.Queries, d.Images, user.ID); err != nil {
		log.Printf("CRITICAL: failed to delete user %d from the deletion page: %v", user.ID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not delete the account")
		return
	}

	// the id and nothing else: every other field was data the user just asked us to forget
	log.Printf("User %d deleted their account from the deletion page", user.ID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}

func (d *AccountDeletion) accountExists(ctx context.Context, phone string) (bool, error) {
	if _, err := d.Queries.GetUserByPhone(ctx, phone); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// long enough for a shop's worth of photos on R2 (two round trips each), short of nginx's 60s cut
const photoRemovalBudget = 30 * time.Second

// eraseAccount deletes an account and then the photos its owner uploaded; the app's path and the web
// page's both end here.
//
// **the paths are read before the delete**, which cascades through shops and products and leaves no
// row naming those files. **the rows go before the files**, so a failure part-way leaves orphans for
// the sweep rather than a row naming a file that is gone.
func eraseAccount(ctx context.Context, q *db.Queries, images imagestore.Storage, userID int64) error {
	uploads, err := q.ListUploadedImagesOfUser(ctx, userID)
	if err != nil {
		return fmt.Errorf("listing the photos of user %d: %w", userID, err)
	}
	if err := q.DeleteUser(ctx, userID); err != nil {
		return fmt.Errorf("deleting user %d: %w", userID, err)
	}
	removeUploads(ctx, images, userID, uploads)
	return nil
}

// removeUploads unlinks the photos of an account that is already deleted. a photo that cannot be
// removed does not undo anything: it is logged and left for the orphan sweep.
func removeUploads(ctx context.Context, images imagestore.Storage, userID int64, uploads []string) {
	// detached from the request: the account is already gone, and a client hanging up now must not
	// strand its photos in the bucket
	removeCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), photoRemovalBudget)
	defer cancel()

	failed := 0
	for _, rel := range uploads {
		if err := images.Remove(removeCtx, rel); err != nil {
			failed++
		}
	}
	if failed > 0 {
		log.Printf("WARNING: user %d deleted, %d of %d photos left for the orphan sweep", userID, failed, len(uploads))
	}
}
