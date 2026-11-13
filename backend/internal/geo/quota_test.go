package geo

// against a real postgres, because the cap is a sql statement: the window and the refusal live there.

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/joho/godotenv"

	"domix/backend/db"
)

func quotaUnderTest(t *testing.T, cap int32) (*DailyQuota, context.Context, pgx.Tx) {
	t.Helper()

	if os.Getenv("DB_URL") == "" {
		_ = godotenv.Load(filepath.Join("..", "..", "..", ".env"))
	}
	dbURL := os.Getenv("DB_URL")
	if dbURL == "" {
		t.Skip("DB_URL is not set - skipping the tests that need a real database")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	t.Cleanup(cancel)

	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		t.Skipf("cannot reach the database (%v) - skipping", err)
	}
	t.Cleanup(func() { _ = conn.Close(context.Background()) })

	tx, err := conn.Begin(ctx)
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	t.Cleanup(func() { _ = tx.Rollback(context.Background()) })

	// **the caps here are counted in tens, and a developer who ran the app has hundreds of real calls
	// in this table**: without emptying it first the window is already over the cap before the test
	// records anything. safe because the transaction is rolled back.
	if _, err := tx.Exec(ctx, `DELETE FROM geo_calls`); err != nil {
		t.Fatalf("clearing geo_calls (run the migrations?): %v", err)
	}

	return &DailyQuota{queries: db.New(tx), cap: cap}, ctx, tx
}

func recordCalls(t *testing.T, ctx context.Context, tx pgx.Tx, product string, hoursAgo, used int) {
	t.Helper()
	if _, err := tx.Exec(ctx,
		`INSERT INTO geo_calls (product, hour, used) VALUES ($1, date_trunc('hour', now()) - make_interval(hours => $2), $3)`,
		product, hoursAgo, used); err != nil {
		t.Fatalf("recording calls (run the migrations?): %v", err)
	}
}

func spend(t *testing.T, ctx context.Context, quota *DailyQuota, product string) bool {
	t.Helper()
	ok, err := quota.Spend(ctx, product)
	if err != nil {
		t.Fatalf("spend: %v", err)
	}
	return ok
}

func TestTheQuotaRefusesTheCallPastTheCap(t *testing.T) {
	quota, ctx, tx := quotaUnderTest(t, 10)
	recordCalls(t, ctx, tx, productGeocoder, 5, 9)

	if !spend(t, ctx, quota, productGeocoder) {
		t.Fatal("the tenth call is inside the cap")
	}
	if spend(t, ctx, quota, productGeocoder) {
		t.Fatal("the eleventh call must be refused")
	}
}

// **a calendar day would hand out the whole budget again at midnight**, and nobody knows whose midnight
// yandex counts from: only the last 24 hours bound every possible day
// subtests rather than one body, so each transaction is rolled back before the next one opens: both
// clear geo_calls, and two open at once would wait on each other until the context expires.
func TestTheQuotaCountsTheLast24HoursNotACalendarDay(t *testing.T) {
	t.Run("23 hours ago still counts", func(t *testing.T) {
		quota, ctx, tx := quotaUnderTest(t, 10)
		recordCalls(t, ctx, tx, productGeocoder, 23, 10)

		if spend(t, ctx, quota, productGeocoder) {
			t.Fatal("calls made 23 hours ago still count")
		}
	})

	t.Run("a full day old does not", func(t *testing.T) {
		quota, ctx, tx := quotaUnderTest(t, 10)
		recordCalls(t, ctx, tx, productGeocoder, 24, 10)

		if !spend(t, ctx, quota, productGeocoder) {
			t.Fatal("calls a full day old no longer count")
		}
	})
}

func TestEachKeyHasABudgetOfItsOwn(t *testing.T) {
	quota, ctx, tx := quotaUnderTest(t, 10)
	recordCalls(t, ctx, tx, productGeocoder, 1, 10)

	if !spend(t, ctx, quota, productSuggest) {
		t.Fatal("a spent geocoder budget must not stop suggestions")
	}
}

// the panel's figure is the one the cap is read against: the same 24 hours, nothing older
func TestUsageCountsTheWindowTheCapRefusesOn(t *testing.T) {
	quota, ctx, tx := quotaUnderTest(t, 10)
	recordCalls(t, ctx, tx, productGeocoder, 0, 2)
	recordCalls(t, ctx, tx, productGeocoder, 23, 5)
	recordCalls(t, ctx, tx, productGeocoder, 24, 7)

	usage, err := quota.Usage(ctx)
	if err != nil {
		t.Fatalf("usage: %v", err)
	}
	want := []Usage{
		{Product: productGeocoder, ThisHour: 2, LastDay: 7, DailyCap: 10},
		{Product: productSuggest, DailyCap: 10},
	}
	if len(usage) != len(want) || usage[0] != want[0] || usage[1] != want[1] {
		t.Fatalf("usage = %+v, want %+v", usage, want)
	}

	for range 3 {
		spend(t, ctx, quota, productGeocoder)
	}
	if spend(t, ctx, quota, productGeocoder) {
		t.Fatal("seven used of ten, three more spent: the eleventh must be refused")
	}
}
