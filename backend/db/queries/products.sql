-- name: SeedTemplateProduct :exec
-- in_basket, specs and section are copied from the template rather than defaulted: a shop created
-- today must hold the same basket as one created last month, or the two totals are not comparable.
INSERT INTO products (shop_id, name, category, unit, template_key, image_path,
                      in_basket, specs, section)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9);

-- name: ListProductsByShop :many
SELECT id, shop_id, name, price, category, unit, availability, template_key, image_path, in_basket, specs, section
FROM products
WHERE shop_id = $1
ORDER BY (template_key IS NULL), id;

-- name: CreateCustomProduct :one
-- in_basket is written FALSE rather than left to the column default: an owner's own product is theirs
-- alone, and the shared basket must hold the same rows in every shop of a market.
INSERT INTO products (shop_id, name, price, category, unit, availability, in_basket)
VALUES ($1, $2, $3, $4, $5, $6, FALSE)
RETURNING id, shop_id, name, price, category, unit, availability, template_key, image_path, in_basket, specs, section;

-- name: CountCustomProducts :one
SELECT COUNT(*)::bigint FROM products WHERE shop_id = $1 AND template_key IS NULL;

-- name: UpdateProduct :one
UPDATE products
SET name = $2,
    price = $3,
    category = $4,
    unit = $5,
    availability = $6,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_id, name, price, category, unit, availability, template_key, image_path, in_basket, specs, section;

-- name: UpdateProductPricing :one
UPDATE products
SET price = $2,
    availability = $3,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_id, name, price, category, unit, availability, template_key, image_path, in_basket, specs, section;

-- name: UpdateProductSlot :one
UPDATE products
SET name = $2,
    price = $3,
    availability = $4,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_id, name, price, category, unit, availability, template_key, image_path, in_basket, specs, section;

-- name: GetProduct :one
SELECT id, shop_id, name, price, category, unit, availability, template_key, image_path, in_basket, specs, section
FROM products WHERE id = $1;

-- name: DeleteProduct :execrows
DELETE FROM products WHERE id = $1;

-- name: ListProductsByCategory :many
-- **a few offers of one product, then the next product.** Every universal shop prices the same 1kg
-- glue, so ordering the category by price alone answers it with two hundred glues before its second
-- product - the page would have to be scrolled past every shop in Tashkent to find out what else is
-- in it. The cheapest line still leads, so the category opens on the best price in it.
--
-- A line is the template key: the rows seeded from one curated product, one size each (000007). An
-- owner's own row has no key and lines up on its name and size instead - the only thing two shops'
-- custom rows ever share.
--
-- **offers_per_line carries a cast or sqlc cannot compile this**: it has no type for a parameter
-- compared against a column a subquery invented, and fails with `column "offer_rank" does not exist`.
SELECT id, shop_id, name, specs, price, category, unit, availability, template_key, image_path, shop_name
FROM (
  SELECT p.id, p.shop_id, p.name, p.specs, p.price, p.category, p.unit, p.availability, p.template_key,
         p.image_path, s.name AS shop_name,
         coalesce(p.template_key, lower(p.name || ' ' || p.specs)) AS line,
         row_number() OVER (
           PARTITION BY coalesce(p.template_key, lower(p.name || ' ' || p.specs))
           ORDER BY (p.availability = 'unavailable'), p.price ASC, p.id
         ) AS offer_rank,
         min(p.price) OVER (
           PARTITION BY coalesce(p.template_key, lower(p.name || ' ' || p.specs))
         ) AS line_price
  FROM products p
  JOIN shops s ON s.id = p.shop_id
  WHERE p.category = $1
    AND p.price IS NOT NULL
) offers
WHERE offer_rank <= @offers_per_line::bigint
ORDER BY line_price ASC, line, offer_rank
LIMIT @result_limit;

-- name: SearchProducts :many
-- the text expression must stay character for character the one idx_products_search_text indexes
-- (migration 000007): postgres uses an expression index only for the identical expression.
SELECT p.id, p.shop_id, p.name, p.specs, p.price, p.category, p.unit, p.availability, p.template_key,
       p.image_path, s.name AS shop_name
FROM products p
JOIN shops s ON s.id = p.shop_id
WHERE p.price IS NOT NULL
  AND translate(lower(p.name || ' ' || p.specs), 'ё', 'е') ~ @anchor::text
  AND translate(lower(p.name || ' ' || p.specs), 'ё', 'е') ~ ALL (@patterns::text[])
ORDER BY (p.availability = 'unavailable'), p.price ASC, p.id
LIMIT @result_limit;

-- name: SetProductImage :one
UPDATE products
SET image_path = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_id, name, price, category, unit, availability, template_key, image_path, in_basket, specs, section;
