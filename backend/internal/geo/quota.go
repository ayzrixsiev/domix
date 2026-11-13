package geo

import (
	"context"
	"errors"
	"log"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
)

// DailyCap is how many calls each product may make in any 24 hours: **ten under yandex's 1000 and no
// lower**, so the app's own «Поиск адресов сейчас недоступен» answers before yandex starts refusing.
// it is not a margin against the bill - going past 1000 is a paid plan, bought in the cabinet.
const DailyCap = 990

// DailyQuota counts calls in postgres (geo_calls), so the count survives the restart every deploy is.
type DailyQuota struct {
	queries *db.Queries

	// **one process is the only writer, and this is what makes the cap exact**: the statement reads the
	// sum and writes in two steps, so two spends at once could both pass at 989.
	mu    sync.Mutex
	swept time.Time
	cap   int32
}

func NewDailyQuota(queries *db.Queries) *DailyQuota {
	return &DailyQuota{queries: queries, cap: DailyCap}
}

func (q *DailyQuota) Spend(ctx context.Context, product string) (bool, error) {
	q.mu.Lock()
	defer q.mu.Unlock()

	_, err := q.queries.SpendGeoCall(ctx, db.SpendGeoCallParams{Product: product, DailyCap: q.cap})
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}

	if time.Since(q.swept) > time.Hour {
		q.swept = time.Now()
		if err := q.queries.ForgetOldGeoCalls(ctx); err != nil {
			log.Printf("WARNING: could not delete old geo_calls rows: %v", err)
		}
	}
	return true, nil
}

// Usage is one product's calls this hour and over the window its cap is counted in.
type Usage struct {
	Product           string
	ThisHour, LastDay int32
	DailyCap          int32
}

// Usage answers every product, a quiet one with zeros, in a fixed order. it reads without the mutex:
// it writes nothing, and a figure one call behind is still the right figure.
func (q *DailyQuota) Usage(ctx context.Context) ([]Usage, error) {
	rows, err := q.queries.GeoUsage(ctx)
	if err != nil {
		return nil, err
	}
	out := []Usage{{Product: productGeocoder, DailyCap: q.cap}, {Product: productSuggest, DailyCap: q.cap}}
	for _, row := range rows {
		for i := range out {
			if out[i].Product == row.Product {
				out[i].ThisHour, out[i].LastDay = row.ThisHour, row.LastDay
			}
		}
	}
	return out, nil
}
