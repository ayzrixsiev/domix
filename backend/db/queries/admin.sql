-- name: AdminOverview :one
SELECT
    (SELECT COUNT(*) FROM users)::bigint                                                    AS users_total,
    (SELECT COUNT(*) FROM users WHERE role = 'customer')::bigint                            AS users_customers,
    (SELECT COUNT(*) FROM users WHERE role = 'shop_owner')::bigint                          AS users_shop_owners,
    (SELECT COUNT(*) FROM users WHERE role = 'admin')::bigint                               AS users_admins,
    (SELECT COUNT(*) FROM users
      WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days')::bigint                    AS users_new_7d,
    (SELECT COUNT(*) FROM users
      WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days')::bigint                   AS users_new_30d,

    (SELECT COUNT(*) FROM shops)::bigint                                                    AS shops_total,
    (SELECT COUNT(*) FROM shops
      WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days')::bigint                    AS shops_new_7d,
    (SELECT COUNT(*) FROM shops WHERE vip_until > CURRENT_TIMESTAMP)::bigint                AS shops_vip,
    (SELECT COUNT(*) FROM shop_basket_index)::bigint                                        AS shops_ranked,

    (SELECT COUNT(*) FROM products)::bigint                                                 AS products_total,
    (SELECT COUNT(price) FROM products)::bigint                                             AS products_priced,
    (SELECT COUNT(*) FROM products WHERE template_key IS NULL)::bigint                      AS products_custom;

-- name: AdminSignupsByDay :many
SELECT
    to_char(d.day, 'YYYY-MM-DD')::text AS day,
    (SELECT COUNT(*) FROM users u
      WHERE u.created_at >= d.day AND u.created_at < d.day + INTERVAL '1 day')::bigint AS users,
    (SELECT COUNT(*) FROM shops s
      WHERE s.created_at >= d.day AND s.created_at < d.day + INTERVAL '1 day')::bigint AS shops
FROM generate_series(
        date_trunc('day', CURRENT_TIMESTAMP) - INTERVAL '29 days',
        date_trunc('day', CURRENT_TIMESTAMP),
        INTERVAL '1 day'
     ) AS d(day)
ORDER BY d.day;

-- name: AdminShopsByCategory :many
SELECT
    s.category,
    COUNT(*)::bigint                                                        AS shops,
    COUNT(bi.shop_id)::bigint                                               AS ranked,
    (COUNT(*) FILTER (WHERE s.vip_until > CURRENT_TIMESTAMP))::bigint       AS vip
FROM shops s
LEFT JOIN shop_basket_index bi ON bi.shop_id = s.id
GROUP BY s.category
ORDER BY COUNT(*) DESC, s.category;

-- name: AdminProductsByCategory :many
SELECT
    p.category,
    COUNT(*)::bigint      AS total,
    COUNT(p.price)::bigint AS priced
FROM products p
GROUP BY p.category
ORDER BY COUNT(*) DESC, p.category;

-- name: AdminListUsers :many
SELECT
    u.id, u.name, u.phone, u.role, u.created_at,
    (SELECT COUNT(*) FROM shops s WHERE s.user_id = u.id)::bigint AS shop_count
FROM users u
ORDER BY u.created_at DESC, u.id DESC
LIMIT $1 OFFSET $2;

-- name: AdminListShops :many
SELECT
    s.id, s.name, s.category, s.address, s.contact_phone, s.created_at, s.vip_until,
    s.excluded_from_index, s.image_path,
    COALESCE(s.vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip,
    u.id    AS owner_id,
    u.name  AS owner_name,
    u.phone AS owner_phone,
    (SELECT COUNT(*) FROM products p WHERE p.shop_id = s.id)::bigint AS products_total,
    (SELECT COUNT(*) FROM products p
      WHERE p.shop_id = s.id AND p.template_key IS NOT NULL)::bigint AS template_total,
    (SELECT COUNT(p.price) FROM products p
      WHERE p.shop_id = s.id AND p.template_key IS NOT NULL)::bigint AS template_priced,
    bi.price_index,
    bi.basket_price
FROM shops s
JOIN users u ON u.id = s.user_id
LEFT JOIN shop_basket_index bi ON bi.shop_id = s.id
ORDER BY s.created_at DESC, s.id DESC
LIMIT $1 OFFSET $2;

-- name: AdminSetShopExcluded :one
UPDATE shops
SET excluded_from_index = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, excluded_from_index;

-- name: AdminDeleteUser :execrows
DELETE FROM users WHERE id = $1;

-- name: AdminCountAdmins :one
-- the one number standing between the panel and locking itself out: there is no way back from zero
-- administrators except SQL on production. not in a transaction with the write it guards, so two
-- admins demoting each other in the same second could both pass.
SELECT COUNT(*)::bigint AS admins FROM users WHERE role = 'admin';

-- name: AdminUpdateUser :one
UPDATE users
SET name = $2,
    role = $3,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, phone, role, created_at;

-- name: AdminPriceAnomalies :many
-- a row here ends with somebody ringing the shop, so both numbers travel: contact_phone is the
-- shop's own line, owner_phone is the account the price was typed from.
WITH comparable AS (
    SELECT p.id, p.shop_id, p.name, p.template_key, p.price,
           s.category AS shop_category, s.name AS shop_name, s.contact_phone,
           u.name  AS owner_name,
           u.phone AS owner_phone
    FROM products p
    JOIN shops s ON s.id = p.shop_id
    JOIN users u ON u.id = s.user_id
    WHERE p.template_key IS NOT NULL AND p.price IS NOT NULL
),
market AS (
    SELECT shop_category, template_key,
           COUNT(*)::bigint                                                AS shops,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price)::float8      AS median_price
    FROM comparable
    GROUP BY shop_category, template_key
    HAVING COUNT(*) >= $1::bigint
)
SELECT c.id                                                        AS product_id,
       c.shop_id,
       c.shop_name,
       c.shop_category,
       c.contact_phone,
       c.owner_name,
       c.owner_phone,
       c.name,
       c.template_key,
       COALESCE(c.price, 0)::bigint                                AS price,
       ROUND(m.median_price)::bigint                               AS median_price,
       m.shops,
       ROUND(((COALESCE(c.price, 0)::float8 - m.median_price) / m.median_price) * 100)::bigint
                                                                   AS deviation_percent
FROM comparable c
JOIN market m ON m.shop_category = c.shop_category AND m.template_key = c.template_key
WHERE m.median_price > 0
  AND ABS(COALESCE(c.price, 0)::float8 - m.median_price) / m.median_price >= $2::float8
ORDER BY ABS(COALESCE(c.price, 0)::float8 - m.median_price) / m.median_price DESC, c.id
LIMIT $3;

-- name: AdminTemplateStatus :one
SELECT
    (SELECT COUNT(*) FROM shops WHERE shops.category = $1)::bigint AS shops,
    (SELECT COUNT(*) FROM products p JOIN shops s ON s.id = p.shop_id
      WHERE s.category = $1 AND p.template_key = ANY($2::text[]))::bigint AS present_rows,
    (SELECT COUNT(*) FROM products p JOIN shops s ON s.id = p.shop_id
      WHERE s.category = $1
        AND p.template_key IS NOT NULL
        AND NOT (p.template_key = ANY($2::text[])))::bigint AS stale_rows;

-- name: AdminTemplateChangedRows :one
-- shop rows whose copy disagrees with the template - exactly the rows AdminSyncTemplateUpdate would
-- rewrite, so the two must compare the same columns, $3 included. **without this the panel said
-- "every shop matches" after a rename**, and with in_basket that lie would hide a basket only half
-- a market has.
SELECT COUNT(*)::bigint
FROM products p
JOIN shops s ON s.id = p.shop_id
JOIN product_templates t ON t.template_key = p.template_key
WHERE s.category = $1
  AND t.shop_category = $1
  AND (
        ($2::boolean AND p.name IS DISTINCT FROM t.name)
        OR p.category      IS DISTINCT FROM t.category
        OR p.unit          IS DISTINCT FROM t.unit
        OR p.image_path    IS DISTINCT FROM
           CASE WHEN p.image_path LIKE $3::text THEN p.image_path ELSE NULLIF(t.image_path, '') END
        OR p.in_basket     IS DISTINCT FROM t.in_basket
        OR p.specs         IS DISTINCT FROM t.specs
        OR p.section       IS DISTINCT FROM t.section
      );

-- name: AdminSyncTemplateInsert :execrows
INSERT INTO products (shop_id, name, category, unit, template_key, image_path,
                      in_basket, specs, section)
SELECT s.id, t.name, t.category, t.unit, t.template_key, NULLIF(t.image_path, ''),
       t.in_basket, t.specs, t.section
FROM shops s
CROSS JOIN jsonb_to_recordset($2::jsonb)
        AS t(template_key text, name text, category text, unit text, image_path text,
             in_basket boolean, specs text, section text)
WHERE s.category = $1
ON CONFLICT (shop_id, template_key) DO NOTHING;

-- name: AdminSyncTemplateUpdate :execrows
-- price and availability are absent from the SET list and that is why this is safe to run at all.
-- **in_basket is here**, though: membership is the template's decision, not the shop's, and a row
-- the panel voted into the basket that stayed out of it in half the shops would mean two markets
-- totalling different baskets under one badge.
--
-- **a shop pointing at its own upload keeps it ($4 is imagestore.UploadDir + '/%').** The owner
-- photographed the roll of wallpaper actually standing in their shop; the template row it sits
-- under names a kind of product, not a product. Overwriting that would replace every real photo in
-- the market with one picture and send the files they replaced to the orphan sweep - silently, with
-- the row count looking exactly as it should. The rule is the prefix rather than the category, so a
-- second slot-based category is covered the day it exists.
UPDATE products p
SET name          = CASE WHEN $3::boolean THEN t.name ELSE p.name END,
    category      = t.category,
    unit          = t.unit,
    image_path    = CASE WHEN p.image_path LIKE $4::text THEN p.image_path
                         ELSE NULLIF(t.image_path, '') END,
    in_basket     = t.in_basket,
    specs         = t.specs,
    section       = t.section,
    updated_at    = CURRENT_TIMESTAMP
FROM shops s,
     jsonb_to_recordset($2::jsonb)
        AS t(template_key text, name text, category text, unit text, image_path text,
             in_basket boolean, specs text, section text)
WHERE p.shop_id = s.id
  AND s.category = $1
  AND p.template_key = t.template_key
  AND (
        (CASE WHEN $3::boolean THEN t.name ELSE p.name END) IS DISTINCT FROM p.name
        OR p.category      IS DISTINCT FROM t.category
        OR p.unit          IS DISTINCT FROM t.unit
        OR p.image_path    IS DISTINCT FROM
           CASE WHEN p.image_path LIKE $4::text THEN p.image_path ELSE NULLIF(t.image_path, '') END
        OR p.in_basket     IS DISTINCT FROM t.in_basket
        OR p.specs         IS DISTINCT FROM t.specs
        OR p.section       IS DISTINCT FROM t.section
      );

-- name: AdminSyncTemplateDelete :execrows
DELETE FROM products p
USING shops s
WHERE p.shop_id = s.id
  AND s.category = $1
  AND p.template_key IS NOT NULL
  AND NOT (p.template_key = ANY($2::text[]));

-- name: ListProductTemplates :many
SELECT shop_category, template_key, name, category, unit, image_path,
       in_basket, specs, section
FROM product_templates
ORDER BY shop_category, id;

-- name: AdminListTemplateItems :many
SELECT id, shop_category, template_key, name, category, unit, image_path,
       in_basket, specs, section
FROM product_templates
WHERE shop_category = $1
ORDER BY id;

-- name: AdminGetTemplateItem :one
-- the row an edit is about, read before it is written: image_path is only valid for one category's
-- own folder, and the id in the url is all the panel sends.
SELECT id, shop_category, template_key, name, category, unit, image_path,
       in_basket, specs, section
FROM product_templates
WHERE id = $1;

-- name: AdminCreateTemplateItem :one
INSERT INTO product_templates (shop_category, template_key, name, category, unit, image_path,
                               in_basket, specs, section)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
RETURNING id, shop_category, template_key, name, category, unit, image_path,
          in_basket, specs, section;

-- name: AdminUpdateTemplateItem :one
-- no SET for template_key: changing it would orphan every shop seeded with the old one and the next
-- sync would delete those rows, losing every price with the row count looking unchanged.
UPDATE product_templates
SET name = $2,
    category = $3,
    unit = $4,
    image_path = $5,
    in_basket = $6,
    specs = $7,
    section = $8,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_category, template_key, name, category, unit, image_path,
          in_basket, specs, section;

-- name: AdminTemplateCoverage :many
-- how many shops of this market have typed a price for each template row. **this is the number that
-- decides when a product can be voted into the basket**: doing it before most shops have priced it
-- takes the rest out of the comparison, which is the exact problem in_basket exists to avoid.
SELECT p.template_key,
       COUNT(*)::bigint            AS present,
       COUNT(p.price)::bigint      AS priced
FROM products p
JOIN shops s ON s.id = p.shop_id
WHERE s.category = $1
  AND p.template_key IS NOT NULL
GROUP BY p.template_key;

-- name: AdminReferencedImagePaths :many
-- every photo path any row points at, templates and shop catalogues together. the catalogue sweep
-- compares the files on disk against this; a path missing from it is a file nothing draws.
SELECT image_path FROM product_templates WHERE image_path IS NOT NULL AND image_path <> ''
UNION
SELECT image_path FROM products WHERE image_path IS NOT NULL AND image_path <> ''
UNION
SELECT image_path FROM shops WHERE image_path IS NOT NULL AND image_path <> '';

-- name: AdminDeleteTemplateItem :one
DELETE FROM product_templates WHERE id = $1
RETURNING id, shop_category, template_key;

-- name: AdminTemplateKeyExists :one
SELECT EXISTS(SELECT 1 FROM product_templates WHERE template_key = $1)::boolean;

-- name: AdminCatalogueFunnel :one
WITH progress AS (
    SELECT s.id,
           s.created_at,
           COUNT(p.id)::bigint    AS template_rows,
           COUNT(p.price)::bigint AS priced_rows
    FROM shops s
    -- basket rows only: a row outside the basket left unpriced does not keep a shop out of the
    -- comparison any more, so counting it here would report a shortfall that does not exist
    LEFT JOIN products p ON p.shop_id = s.id AND p.template_key IS NOT NULL AND p.in_basket
    GROUP BY s.id
),
scored AS (
    SELECT *,
           CASE WHEN template_rows > 0 THEN priced_rows::float8 / template_rows * 100 ELSE 0 END AS pct
    FROM progress
)
-- three buckets and not five, because a catalogue is either complete or it is not in the comparison:
-- 50% and 90% are the same outcome as 1%. who is closest to the line is answered by
-- AdminShopsNeedingAttention, by name and phone number, rather than by a band.
SELECT
    COUNT(*)::bigint                                                       AS shops,
    (COUNT(*) FILTER (WHERE priced_rows = 0))::bigint                      AS empty,
    (COUNT(*) FILTER (WHERE pct > 0 AND pct < 100))::bigint                AS started,
    (COUNT(*) FILTER (WHERE pct >= 100))::bigint                           AS complete
FROM scored;

-- name: AdminShopsNeedingAttention :many
-- every shop whose catalogue is not finished, nearest the line first. the limit is a ceiling rather
-- than a page; the day it is not, this grows a page rather than a second endpoint.
SELECT s.id,
       s.name,
       s.category,
       s.created_at,
       s.contact_phone,
       u.name  AS owner_name,
       u.phone AS owner_phone,
       COUNT(p.id)::bigint                                            AS template_rows,
       COUNT(p.price)::bigint                                         AS priced_rows,
       (COUNT(p.id) - COUNT(p.price))::bigint                         AS remaining
FROM shops s
JOIN users u ON u.id = s.user_id
JOIN products p ON p.shop_id = s.id AND p.template_key IS NOT NULL AND p.in_basket
GROUP BY s.id, u.name, u.phone
HAVING COUNT(p.price) < COUNT(p.id)
ORDER BY (COUNT(p.id) - COUNT(p.price)), s.created_at
LIMIT $1;

-- name: AdminMarketRankings :many
-- the cheapest few shops in every market, in order, because the question the panel exists to answer
-- is **whether anybody is competing**: 4.61/4.63/4.65 is a fight, 4.6/5.4/6.2 is one shop with no
-- pressure on it, and the two look identical if you print only the winner.
--
-- CROSS JOIN LATERAL and not a window function: sqlc cannot compile a ROW_NUMBER() filtered from an
-- outer WHERE, and the lateral is the shape postgres wants anyway.
SELECT c.category,
       r.shop_id,
       r.shop_name,
       r.price_index,
       r.basket_price
FROM (SELECT DISTINCT category FROM shops) c
CROSS JOIN LATERAL (
    SELECT s.id AS shop_id, s.name AS shop_name, bi.price_index, bi.basket_price
    FROM shops s
    JOIN shop_basket_index bi ON bi.shop_id = s.id
    WHERE s.category = c.category
    ORDER BY bi.price_index, s.id
    LIMIT $1
) r
ORDER BY c.category, r.price_index, r.shop_id;

-- name: AdminCategoryBaskets :many
-- what a basket costs in each market right now, and how far apart its shops are. it joins the index
-- table, so **only complete catalogues are in it** - the same rule the app's badge follows, which is
-- what keeps the two numbers agreeing.
SELECT s.category,
       COUNT(*)::bigint                          AS shops,
       ROUND(AVG(bi.basket_price))::bigint       AS avg_basket,
       MIN(bi.basket_price)::bigint              AS min_basket,
       MAX(bi.basket_price)::bigint              AS max_basket
FROM shops s
JOIN shop_basket_index bi ON bi.shop_id = s.id
GROUP BY s.category
ORDER BY s.category;

-- name: RecordBasketHistory :exec
-- today's row for every market, written by the hourly job in cmd/api/main.go. the upsert is what
-- makes running it twice an hour identical to running it once a day. a market with no shops in the
-- comparison writes no row rather than a zero, which would claim the basket was free.
INSERT INTO basket_history (day, category, shops, avg_basket, min_basket, max_basket)
SELECT CURRENT_DATE,
       s.category,
       COUNT(*)::int,
       ROUND(AVG(bi.basket_price))::bigint,
       MIN(bi.basket_price)::bigint,
       MAX(bi.basket_price)::bigint
FROM shops s
JOIN shop_basket_index bi ON bi.shop_id = s.id
GROUP BY s.category
ON CONFLICT (day, category) DO UPDATE
SET shops      = EXCLUDED.shops,
    avg_basket = EXCLUDED.avg_basket,
    min_basket = EXCLUDED.min_basket,
    max_basket = EXCLUDED.max_basket;

-- name: AdminBasketHistory :many
-- the last 30 days of every market. no generate_series, unlike AdminSignupsByDay: a missing day is a
-- day the server was not running, and a zero would draw a market that briefly cost nothing.
SELECT to_char(day, 'YYYY-MM-DD')::text AS day,
       category,
       shops,
       avg_basket
FROM basket_history
WHERE day >= CURRENT_DATE - 29
ORDER BY day, category;

-- name: AdminVipPlacements :many
SELECT s.id, s.name, s.category, s.vip_until,
       (EXTRACT(EPOCH FROM (s.vip_until - CURRENT_TIMESTAMP)) / 86400)::int AS days_left
FROM shops s
WHERE s.vip_until > CURRENT_TIMESTAMP
ORDER BY s.vip_until
LIMIT $1;

-- name: AdminUploadedImagePaths :many
-- every uploaded photo any row points at, for the orphan sweep. filtered in SQL because catalogue
-- paths outnumber uploads a hundred to one. the prefix is a parameter so imagestore.UploadDir stays
-- the one declaration of what "uploads/" is.
--
-- **shops are in it, not only products**: a storefront photo lives in the same directory, and a
-- sweep that read products alone would delete every VIP card's picture an hour after it was uploaded.
SELECT image_path::text AS image_path
FROM products
WHERE image_path LIKE @prefix::text
UNION
SELECT image_path::text AS image_path
FROM shops
WHERE image_path LIKE @prefix::text;
