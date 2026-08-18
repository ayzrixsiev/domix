-- name: SeedTemplateProduct :exec
-- one row of the category template (internal/catalog), written inside the same transaction as the
-- shop itself. price is left out of the column list rather than passed as 0: the owner has not set
-- one yet, and NULL is what "not set" means.
INSERT INTO products (shop_id, name, category, unit, template_key, image_path)
VALUES ($1, $2, $3, $4, $5, $6);

-- name: ListProductsByShop :many
-- the shop's whole catalogue, for both the owner's grid and the customer-facing one. no pagination:
-- at most 99 template rows plus 20 of the owner's own, so it is one small response by construction.
-- template rows first, in template order - false sorts before true in postgres, so
-- `template_key IS NULL` ascending puts them on top, and id follows insertion order.
SELECT id, shop_id, name, price, category, unit, availability, template_key, image_path
FROM products
WHERE shop_id = $1
ORDER BY (template_key IS NULL), id;

-- name: CreateCustomProduct :one
-- a product the owner typed in themselves. template_key stays NULL, which is what makes it "custom"
-- and what CountCustomProducts counts against the 20-product allowance.
INSERT INTO products (shop_id, name, price, category, unit, availability)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING id, shop_id, name, price, category, unit, availability, template_key, image_path;

-- name: CountCustomProducts :one
-- backs the 20-own-products cap. the template rows are what this predicate excludes: a universal
-- shop starts with 99 of them, so counting every row would put a brand-new shop over its limit
-- before the owner had added anything.
SELECT COUNT(*)::bigint FROM products WHERE shop_id = $1 AND template_key IS NULL;

-- name: UpdateProduct :one
-- PUT /api/products/{id} for a product the owner added themselves. the form submits every field, so
-- this is a full replacement. template_key and image_path are absent on purpose: editing a product
-- must not change what it *is*, and there is no photo upload yet.
UPDATE products
SET name = $2,
    price = $3,
    category = $4,
    unit = $5,
    availability = $6,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_id, name, price, category, unit, availability, template_key, image_path;

-- name: UpdateProductPricing :one
-- the same endpoint for a template product, where only these two columns may change.
--
-- name, category and unit are absent from the SET list rather than passed through unchanged, so the
-- rule is enforced by the statement itself: no request body can rename a template row. the template
-- is the shared basket every shop of a category is compared on, and it stops meaning anything the
-- moment one shop can relabel "Кнауф Ротбанд" while keeping its template_key.
UPDATE products
SET price = $2,
    availability = $3,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_id, name, price, category, unit, availability, template_key, image_path;

-- name: UpdateProductSlot :one
-- the same endpoint again for a slot - a template row whose product the owner supplies, as every
-- обои row is. UpdateProductPricing plus name.
--
-- category and unit stay out of the SET list, and that matters more here than above: the ten rows
-- are already ten different products in every shop, so the unit is the last thing holding the
-- comparison together.
UPDATE products
SET name = $2,
    price = $3,
    availability = $4,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_id, name, price, category, unit, availability, template_key, image_path;

-- name: GetProduct :one
-- read back before an edit or delete, so the handler can authorize against the product's *own*
-- shop_id rather than one the client claimed, and can tell a template row from the owner's own.
SELECT id, shop_id, name, price, category, unit, availability, template_key, image_path
FROM products WHERE id = $1;

-- name: DeleteProduct :execrows
-- :execrows returns the number of rows deleted, which is how the handler tells "already gone" apart
-- from "deleted just now".
DELETE FROM products WHERE id = $1;

-- name: ListProductsByCategory :many
-- every priced product in one of the twelve product categories, across every shop - what a
-- "Популярные категории" tile opens onto.
--
-- Priced rows only: an unpriced product is one the owner has not confirmed they stock at a price,
-- and in a cross-shop browse it answers nothing. Custom products are included - "can I buy плитка
-- here" is answered just as truthfully by a product the owner added themselves.
--
-- Cheapest first, so the list opens on the answer. Ties break on shop rating and then id, which is
-- not cosmetic: without a total order postgres may return equally-priced rows in a different
-- sequence each request, and a list that reshuffles under pull-to-refresh reads as broken.
SELECT p.id, p.shop_id, p.name, p.price, p.category, p.unit, p.availability, p.template_key,
       p.image_path, s.name AS shop_name
FROM products p
JOIN shops s ON s.id = p.shop_id
WHERE p.category = $1
  AND p.price IS NOT NULL
ORDER BY p.price ASC, s.rating DESC, p.id
LIMIT $2;

-- name: SearchProducts :many
-- what the home screen's search field asks: "who sells this, and for how much".
--
-- Deliberately the same SELECT list, the same priced-only filter and the same ordering as
-- ListProductsByCategory above, because both feed the identical grid on the app side - a search
-- result and a category result are the same object arriving by a different door, and a row that
-- sorted differently depending on how you got to it would read as a bug.
--
-- ILIKE, not LIKE: postgres LIKE is case-sensitive, so "цемент" would miss a product the owner
-- typed as "Цемент" - which, on a catalogue people fill in by hand, is most of them. The leading
-- wildcard makes this a substring match, so "мешок" finds "Цемент в мешках".
--
-- **A leading `%` cannot use a btree index, so this is a sequential scan of `products`.** That is
-- fine at the scale this launches at (a few thousand rows, well under a millisecond) and it is the
-- honest trade: the alternative is a prefix-only search that fails to find "Цемент М400" when you
-- type "М400". The fix when the table grows is a pg_trgm GIN index on lower(name), which makes
-- ILIKE '%...%' indexable - a migration, not a rewrite of this query.
SELECT p.id, p.shop_id, p.name, p.price, p.category, p.unit, p.availability, p.template_key,
       p.image_path, s.name AS shop_name
FROM products p
JOIN shops s ON s.id = p.shop_id
WHERE p.price IS NOT NULL
  AND p.name ILIKE '%' || @query::text || '%'
ORDER BY p.price ASC, s.rating DESC, p.id
LIMIT @result_limit;
