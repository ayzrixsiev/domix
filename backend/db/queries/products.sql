-- name: SeedTemplateProduct :exec
-- one row of the category template (internal/catalog), written while the shop itself is being
-- created and inside the same transaction. price is left out of the column list entirely rather
-- than passed as 0: the owner has not set one yet, and NULL is what "not set" means (migration
-- 000005). availability falls back to its 'in_stock' default for the same reason - it is the value
-- the owner will most often want, and they can change it per product afterwards.
INSERT INTO products (shop_id, name, category, unit, template_key)
VALUES ($1, $2, $3, $4, $5);

-- name: ListProductsByShop :many
-- the shop's whole catalogue, for both the owner's management grid and the customer-facing grid in
-- the map sheet. template rows come first in the order the template defines them - which is the
-- order they were inserted, hence id - and the owner's own additions follow. in postgres false
-- sorts before true, so `template_key IS NULL` ascending puts the template rows on top.
SELECT id, shop_id, name, price, category, unit, availability, template_key
FROM products
WHERE shop_id = $1
ORDER BY (template_key IS NULL), id;

-- name: CreateCustomProduct :one
-- a product the owner typed in themselves. template_key stays NULL, which is exactly what makes it
-- "custom" and what CountCustomProducts below counts against the 20-product allowance.
INSERT INTO products (shop_id, name, price, category, unit, availability)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING id, shop_id, name, price, category, unit, availability, template_key;

-- name: CountCustomProducts :one
-- how many products this shop's owner added themselves, i.e. everything that did not come from the
-- category template. backs the "20 of your own products" cap.
--
-- the template rows are what this predicate exists to *exclude*: a universal shop starts with 50 of
-- them and the allowance is 20, so counting every row would put a brand-new shop over its limit
-- before the owner had added anything at all.
SELECT COUNT(*)::bigint FROM products WHERE shop_id = $1 AND template_key IS NULL;

-- name: UpdateProduct :one
-- backs PUT /api/products/{id} for a product the owner added themselves: the edit form always
-- submits every field, so this is a full replacement like UpdateShop rather than a per-column
-- patch. template_key is deliberately absent - it identifies the row for cross-shop comparison, and
-- editing a product must not change what it *is*.
UPDATE products
SET name = $2,
    price = $3,
    category = $4,
    unit = $5,
    availability = $6,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_id, name, price, category, unit, availability, template_key;

-- name: UpdateProductPricing :one
-- backs the same endpoint for a *template* product, where only these two columns may change.
--
-- name, category and unit are absent from the SET list rather than being passed through unchanged,
-- so the rule is enforced by the statement itself: there is no request body, however malformed or
-- hand-crafted, that can rename a template row through this query. the template is the shared
-- basket every shop of a category is compared on, and it stops meaning anything the moment one shop
-- can relabel "Цемент М400" as something else while keeping its template_key.
UPDATE products
SET price = $2,
    availability = $3,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_id, name, price, category, unit, availability, template_key;

-- name: GetProduct :one
-- read back before an edit or delete, so the handler can authorize against the product's *own*
-- shop_id rather than one the client claimed, and can tell a template row from the owner's own.
SELECT id, shop_id, name, price, category, unit, availability, template_key
FROM products WHERE id = $1;

-- name: DeleteProduct :execrows
-- :execrows returns the number of rows deleted, which is how the handler tells "already gone" apart
-- from "deleted just now" - the same contract DeleteShop uses.
DELETE FROM products WHERE id = $1;
