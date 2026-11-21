package endpoints

import (
	"context"
	"errors"
	"log"
	"net/http"

	"github.com/jackc/pgx/v5"

	"domix/backend/internal/auth"
)

// **a signed-in shop owner never sees another shop's prices or its place in the index**, the founders'
// call so that sellers cannot copy one another. one price at a time stays public to everybody - search,
// the category drill-down, a saved product - since that is a buyer's question; a competitor's whole
// list and its ranking are a copier's. their own shops they see in full.
//
// a cached read holds one copy per audience and never one per account, which is what keeps it cheap.
type audience string

const (
	buyers  audience = "buyers" // guests, customers and admins
	sellers audience = "sellers"
)

type viewer struct {
	userID   int64 // 0 for a guest
	audience audience
}

type roleReader interface {
	GetUserRole(ctx context.Context, id int64) (string, error)
}

// the role is read from the database like RequireAuth's token version, because a JWT is never trusted
// for one. a token that fails its signature is a guest: signing out shows prices anyway.
func viewerOf(ctx context.Context, r *http.Request, jwtSecret string, roles roleReader) viewer {
	userID, ok := auth.UserIDFromRequest(r, jwtSecret)
	if !ok {
		return viewer{audience: buyers}
	}

	role, err := roles.GetUserRole(ctx, userID)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return viewer{audience: buyers}
	case err != nil:
		// fails towards hiding: a customer losing the badges for a minute is a blip, an owner reading
		// a competitor's list is the thing this exists to stop
		log.Printf("WARNING: cannot read the role of user %d, answering as to a seller: %v", userID, err)
		return viewer{userID: userID, audience: sellers}
	case role == "shop_owner":
		return viewer{userID: userID, audience: sellers}
	default:
		return viewer{userID: userID, audience: buyers}
	}
}

func (v viewer) seesPricesOf(shopOwnerID int64) bool {
	return v.audience == buyers || v.userID == shopOwnerID
}

// the cache key for this audience's copy of a whole-market read
func (v viewer) cacheKey(key string) string {
	if v.audience == sellers {
		return key + ":" + string(sellers)
	}
	return key
}
