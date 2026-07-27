package endpoints

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/xuri/excelize/v2"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
)

// POST /api/products/upload (multipart form: "shop_id" text field + "file" .xlsx) - lets a shop
// owner bulk-populate their shop's product catalog in one request. see db/queries/products.sql for
// the (shop_id, article) upsert this is built on: re-uploading the same file updates existing rows
// by their Артикул instead of duplicating them.
type Products struct {
	Pool      *pgxpool.Pool // needed directly (not just Queries) so the whole upload runs in one transaction
	Queries   *db.Queries
	JWTSecret string
}

const (
	maxUploadBytes = 5 << 20 // 5MB - a 50-row spreadsheet is a few tens of KB at most; this just bounds the worst case
	maxProductRows = 50
	productColumns = 6 // Категория, Наименование товара, Цена, Единица измерения, Наличие, Артикул

	// these mirror the varchar widths in db/migrations (000001 + 000004). a value wider than its
	// column makes postgres reject that INSERT, and since every row shares one transaction (below)
	// that single bad cell would otherwise throw away the entire upload.
	maxCategoryLen = 100
	maxNameLen     = 150
	maxUnitLen     = 20
	maxArticleLen  = 100

	// no construction product costs this much; the ceiling doubles as overflow protection for the
	// float -> int64 conversion in parsePrice
	maxPrice = 1e15
)

// every error response carries a stable machine-readable code next to the human message. the flutter
// app is ru/uz only, so it localizes off the code and never displays these english strings - see
// ProductUploadException in frontend/lib/features/stores/data/product_upload_result.dart.
func writeUploadError(w http.ResponseWriter, status int, code, message string) {
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]any{"error": message, "code": code})
}

func (p *Products) Upload(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeUploadError(w, http.StatusUnauthorized, "unauthorized", "unauthorized")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxUploadBytes)
	if err := r.ParseMultipartForm(maxUploadBytes); err != nil {
		if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
			writeUploadError(w, http.StatusRequestEntityTooLarge, "file_too_large", "file too large")
			return
		}
		writeUploadError(w, http.StatusBadRequest, "invalid_form", "invalid multipart form")
		return
	}

	shopID, err := strconv.ParseInt(r.FormValue("shop_id"), 10, 64)
	if err != nil {
		writeUploadError(w, http.StatusBadRequest, "invalid_shop_id", "missing or invalid shop_id")
		return
	}

	file, _, err := r.FormFile("file")
	if err != nil {
		writeUploadError(w, http.StatusBadRequest, "missing_file", "missing file")
		return
	}
	defer file.Close()

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// authorization has two parts: being a shop_owner/admin at all (role, looked up fresh - see
	// internal/auth/jwt.go for why we never trust a role claim), and - since that alone would let
	// any shop owner upload into someone else's shop - actually owning this specific shop_id.
	role, err := p.Queries.GetUserRole(ctx, userID)
	if err != nil {
		log.Printf("CRITICAL: failed to look up role for user %d: %v", userID, err)
		writeUploadError(w, http.StatusInternalServerError, "server_error", "failed to verify permissions")
		return
	}
	if role != "shop_owner" && role != "admin" {
		writeUploadError(w, http.StatusForbidden, "forbidden_role", "only shop owners can upload products")
		return
	}

	ownerID, err := p.Queries.GetShopOwner(ctx, shopID)
	if err != nil {
		// a genuinely missing shop and a database that just fell over are very different events:
		// reporting the second as "shop not found" would send the owner hunting for a bug in their
		// own data while the real incident goes unlogged
		if errors.Is(err, pgx.ErrNoRows) {
			writeUploadError(w, http.StatusNotFound, "shop_not_found", "shop not found")
			return
		}
		log.Printf("CRITICAL: failed to look up owner of shop %d: %v", shopID, err)
		writeUploadError(w, http.StatusInternalServerError, "server_error", "failed to verify shop ownership")
		return
	}
	if role != "admin" && ownerID != userID {
		writeUploadError(w, http.StatusForbidden, "not_owner", "you do not own this shop")
		return
	}

	xf, err := excelize.OpenReader(file)
	if err != nil {
		writeUploadError(w, http.StatusBadRequest, "invalid_file", "could not read excel file")
		return
	}
	defer xf.Close()

	// an upload-facing file from an untrusted client, unlike a sheet name we picked ourselves -
	// worth guarding even though a structurally valid xlsx can't actually have zero sheets
	sheets := xf.GetSheetList()
	if len(sheets) == 0 {
		writeUploadError(w, http.StatusBadRequest, "invalid_file", "excel file has no sheets")
		return
	}
	rows, err := xf.GetRows(sheets[0])
	if err != nil {
		writeUploadError(w, http.StatusBadRequest, "invalid_file", "could not read excel rows")
		return
	}

	// row 0 is the header (see db/queries/products.sql for the expected column order)
	if len(rows) > 0 {
		rows = rows[1:]
	}

	// spreadsheets routinely carry blank rows the owner never notices - a spacer between groups, a
	// row that once held data. they aren't malformed products, so counting them would both inflate
	// the "skipped" number we report back and eat into the 50-row budget checked below.
	dataRows := make([][]string, 0, len(rows))
	for _, row := range rows {
		if !isBlankRow(row) {
			dataRows = append(dataRows, row)
		}
	}

	if len(dataRows) > maxProductRows {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]any{
			"error": fmt.Sprintf("file has %d products, max is %d per upload", len(dataRows), maxProductRows),
			"code":  "too_many_rows",
			"limit": maxProductRows,
		})
		return
	}

	valid := make([]productRow, 0, len(dataRows))
	skipped := 0
	for _, row := range dataRows {
		parsed, ok := parseProductRow(row)
		if !ok {
			skipped++
			continue
		}
		valid = append(valid, parsed)
	}

	// the whole batch commits or none of it does - a partial write here would leave the shop with
	// some articles updated and others not, from what looks to the owner like a single upload
	tx, err := p.Pool.Begin(ctx)
	if err != nil {
		log.Printf("CRITICAL: failed to begin product upload transaction for shop %d: %v", shopID, err)
		writeUploadError(w, http.StatusInternalServerError, "server_error", "failed to process upload")
		return
	}
	defer tx.Rollback(ctx) // no-op once Commit below succeeds

	qtx := p.Queries.WithTx(tx)
	for _, v := range valid {
		if err := qtx.UpsertProduct(ctx, db.UpsertProductParams{
			ShopID:       shopID,
			Name:         v.name,
			Price:        v.price,
			Category:     v.category,
			Unit:         v.unit,
			Availability: v.availability,
			Article:      pgtype.Text{String: v.article, Valid: true},
		}); err != nil {
			log.Printf("CRITICAL: failed to upsert product (shop %d, article %q): %v", shopID, v.article, err)
			writeUploadError(w, http.StatusInternalServerError, "server_error", "failed to save products")
			return
		}
	}

	if err := tx.Commit(ctx); err != nil {
		log.Printf("CRITICAL: failed to commit product upload for shop %d: %v", shopID, err)
		writeUploadError(w, http.StatusInternalServerError, "server_error", "failed to save products")
		return
	}

	log.Printf("Product upload for shop %d: %d processed, %d skipped", shopID, len(valid), skipped)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]int{
		"rows_in_file": len(dataRows),
		"processed":    len(valid),
		"skipped":      skipped,
	})
}

// one spreadsheet row that survived validation, ready to be written
type productRow struct {
	category, name, unit, availability, article string
	price                                       int64
}

func isBlankRow(row []string) bool {
	for _, cell := range row {
		if strings.TrimSpace(cell) != "" {
			return false
		}
	}
	return true
}

// ok=false means "skip this row and keep going", never "reject the file" - that's the contract the
// whole upload is built around, so every check in here has to be a per-row verdict.
func parseProductRow(row []string) (productRow, bool) {
	if len(row) < productColumns {
		return productRow{}, false
	}

	price, priceOK := parsePrice(row[2])
	availability, availOK := parseAvailability(row[4])
	if !priceOK || !availOK {
		return productRow{}, false
	}

	p := productRow{
		category:     strings.TrimSpace(row[0]),
		name:         strings.TrimSpace(row[1]),
		unit:         strings.TrimSpace(row[3]),
		article:      strings.TrimSpace(row[5]),
		availability: availability,
		price:        price,
	}

	if p.category == "" || p.name == "" || p.unit == "" || p.article == "" {
		return productRow{}, false
	}

	// rune count, not len(): these are cyrillic strings, where one character is two bytes, and
	// postgres counts varchar limits in characters
	if utf8.RuneCountInString(p.category) > maxCategoryLen ||
		utf8.RuneCountInString(p.name) > maxNameLen ||
		utf8.RuneCountInString(p.unit) > maxUnitLen ||
		utf8.RuneCountInString(p.article) > maxArticleLen {
		return productRow{}, false
	}

	return p, true
}

// the excel column is free text in whichever language the owner typed, so a handful of the obvious
// ru/uz spellings get normalised down to the locale-neutral codes the db stores (see migration
// 000004). anything unrecognised skips the row rather than guessing: silently defaulting to
// "in stock" would advertise products the shop doesn't actually have.
func parseAvailability(raw string) (string, bool) {
	s := strings.ToLower(strings.TrimSpace(raw))
	// excel emits real apostrophe characters for uzbek, not the ascii one people type
	s = strings.NewReplacer(" ", " ", " ", " ", "ʻ", "'", "‘", "'", "’", "'", "`", "'").Replace(s)
	s = strings.Join(strings.Fields(s), " ") // collapse doubled inner spaces

	switch s {
	case "есть", "в наличии", "есть в наличии", "имеется", "+", "bor", "mavjud":
		return "in_stock", true
	case "под заказ", "на заказ", "предзаказ", "buyurtma", "buyurtmaga", "buyurtma asosida":
		return "on_order", true
	case "нет", "нет в наличии", "отсутствует", "-", "yo'q", "yoq", "mavjud emas":
		return "unavailable", true
	default:
		return "", false
	}
}

// excelize hands us the cell's *formatted* text, not the underlying number, so the price column
// arrives in whatever shape the owner's cell formatting produced: a plain "45000", a currency
// "1,250,000.00", a ru-locale "1.250.000", a stray "45 000,50". an earlier version accepted only
// plain digits, which meant a currency-formatted column silently skipped every single row.
func parsePrice(raw string) (int64, bool) {
	// nbsp / narrow nbsp are what excel actually puts in a thousands gap, not a plain space
	s := strings.NewReplacer(" ", "", " ", "", " ", "", "'", "").Replace(strings.TrimSpace(raw))
	if s == "" {
		return 0, false
	}

	lastSep := strings.LastIndexAny(s, ".,")
	if lastSep == -1 {
		return parseWholeSom(s)
	}

	switch digitsAfter := len(s) - lastSep - 1; {
	// "1,250,000" / "1.250.000" - exactly three trailing digits is a thousands group, never a
	// fraction: so'm has no subunit anyone quotes prices in
	case digitsAfter == 3:
		return parseWholeSom(stripGroupSeparators(s))

	// "45000.5" / "150,50" / "1,250,000.00" - one or two trailing digits is a real decimal, so drop
	// any thousands separators ahead of it and round to the whole so'm the db column stores
	case digitsAfter == 1 || digitsAfter == 2:
		normalized := stripGroupSeparators(s[:lastSep]) + "." + s[lastSep+1:]
		value, err := strconv.ParseFloat(normalized, 64)
		if err != nil || value < 0 || value > maxPrice {
			return 0, false
		}
		return int64(math.Round(value)), true

	// a trailing separator ("150.") or more precision than any real price carries
	default:
		return 0, false
	}
}

func stripGroupSeparators(s string) string {
	return strings.NewReplacer(".", "", ",", "").Replace(s)
}

func parseWholeSom(s string) (int64, bool) {
	price, err := strconv.ParseInt(s, 10, 64)
	if err != nil || price < 0 || float64(price) > maxPrice {
		return 0, false
	}
	return price, true
}
