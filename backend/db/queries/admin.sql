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
    (SELECT COUNT(*) FROM products WHERE template_key IS NULL)::bigint                      AS products_custom,

    (SELECT COUNT(DISTINCT user_id) FROM support_messages)::bigint                          AS support_threads,
    (SELECT COUNT(*) FROM (
        SELECT m.user_id
        FROM support_messages m
        WHERE NOT m.from_support
          AND m.id > COALESCE((SELECT MAX(s.id) FROM support_messages s
                                WHERE s.user_id = m.user_id AND s.from_support), 0)
        GROUP BY m.user_id
     ) waiting)::bigint                                                                     AS support_awaiting;

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

-- name: AdminDeleteUser :execrows
DELETE FROM users WHERE id = $1;

-- name: AdminCountAdmins :one
--
-- the one number standing between the panel and locking itself out for good. Granting and revoking
-- `admin` are both panel operations now, so the old blanket refusals are gone (see Admin.UpdateUser)
-- - what replaces them is narrower and is not a policy: an account can be demoted or deleted unless
-- it is the last administrator, because there is no way back from zero except SQL on production.
--
-- Read inside the same request as the write and not in a transaction with it, so two admins demoting
-- each other in the same second could in principle both pass. At one machine and one person that is
-- not a race worth a lock; if this ever matters, the honest fix is a partial unique index rather
-- than a bigger check here.
SELECT COUNT(*)::bigint AS admins FROM users WHERE role = 'admin';

-- name: AdminUpdateUser :one
UPDATE users
SET name = $2,
    role = $3,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, phone, role, created_at;

-- name: AdminPriceAnomalies :many
--
-- the report carries the two numbers a phone call needs as well as the two it is about: a row here
-- ends with somebody ringing the shop, and looking the number up in another tab is the step that
-- makes a report get skipped. contact_phone is the shop's own line and owner_phone is the account
-- the price was typed from - they are usually the same and are not always, which is why both are
-- here rather than one being assumed.
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

-- name: AdminSyncTemplateInsert :execrows
INSERT INTO products (shop_id, name, category, unit, template_key, image_path)
SELECT s.id, t.name, t.category, t.unit, t.template_key, NULLIF(t.image_path, '')
FROM shops s
CROSS JOIN jsonb_to_recordset($2::jsonb)
        AS t(template_key text, name text, category text, unit text, image_path text)
WHERE s.category = $1
ON CONFLICT (shop_id, template_key) DO NOTHING;

-- name: AdminSyncTemplateUpdate :execrows
UPDATE products p
SET name       = CASE WHEN $3::boolean THEN t.name ELSE p.name END,
    category   = t.category,
    unit       = t.unit,
    image_path = NULLIF(t.image_path, ''),
    updated_at = CURRENT_TIMESTAMP
FROM shops s,
     jsonb_to_recordset($2::jsonb)
        AS t(template_key text, name text, category text, unit text, image_path text)
WHERE p.shop_id = s.id
  AND s.category = $1
  AND p.template_key = t.template_key
  AND (
        (CASE WHEN $3::boolean THEN t.name ELSE p.name END) IS DISTINCT FROM p.name
        OR p.category   IS DISTINCT FROM t.category
        OR p.unit       IS DISTINCT FROM t.unit
        OR p.image_path IS DISTINCT FROM NULLIF(t.image_path, '')
      );

-- name: AdminSyncTemplateDelete :execrows
DELETE FROM products p
USING shops s
WHERE p.shop_id = s.id
  AND s.category = $1
  AND p.template_key IS NOT NULL
  AND NOT (p.template_key = ANY($2::text[]));

-- name: ListProductTemplates :many
SELECT shop_category, template_key, name, category, unit, image_path
FROM product_templates
ORDER BY shop_category, id;

-- name: AdminListTemplateItems :many
SELECT id, shop_category, template_key, name, category, unit, image_path
FROM product_templates
WHERE shop_category = $1
ORDER BY id;

-- name: AdminCreateTemplateItem :one
INSERT INTO product_templates (shop_category, template_key, name, category, unit, image_path)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING id, shop_category, template_key, name, category, unit, image_path;

-- name: AdminUpdateTemplateItem :one
UPDATE product_templates
SET name = $2,
    category = $3,
    unit = $4,
    image_path = $5,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, shop_category, template_key, name, category, unit, image_path;

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
    LEFT JOIN products p ON p.shop_id = s.id AND p.template_key IS NOT NULL
    GROUP BY s.id
),
scored AS (
    SELECT *,
           CASE WHEN template_rows > 0 THEN priced_rows::float8 / template_rows * 100 ELSE 0 END AS pct
    FROM progress
)
-- three buckets, not five, and the reason is the rule they describe: a catalogue is either
-- complete or it is not in the comparison, so 50% and 90% are the same outcome as 1%. The panel
-- had a «Больше половины» and a «Почти готово» band, which invited reading the funnel as progress
-- towards something when only the last band is worth anything. Who is closest to the line is a
-- real question and it is answered properly by AdminShopsNeedingAttention, by name and phone
-- number, rather than by a count of anonymous shops in a band.
--
-- `stalled` - empty and older than a fortnight - was a fifth number here and is gone with the card
-- that printed it. Every unfinished shop is now one row in the panel's «Не заполнены» list with its
-- own creation date against it, which is the same fact per shop instead of a count of anonymous
-- ones, and nothing was left reading the aggregate.
SELECT
    COUNT(*)::bigint                                                       AS shops,
    (COUNT(*) FILTER (WHERE priced_rows = 0))::bigint                      AS empty,
    (COUNT(*) FILTER (WHERE pct > 0 AND pct < 100))::bigint                AS started,
    (COUNT(*) FILTER (WHERE pct >= 100))::bigint                           AS complete
FROM scored;

-- name: AdminShopsNeedingAttention :many
--
-- every shop whose catalogue is not finished, nearest the line first. It used to be the top 8 behind
-- a «Кому позвонить» card; it is now the whole list behind the gauge's «Не заполнены» box, so the
-- limit is a ceiling rather than a page - 100 rows of five columns is a few kilobytes on a request
-- the panel already makes every 45 seconds, and the day it is not, this grows a page rather than a
-- second endpoint.
--
-- `contact_phone` as well as the owner's: the shop's line is the one to ring about the shop, and
-- they are usually but not always the same number.
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
JOIN products p ON p.shop_id = s.id AND p.template_key IS NOT NULL
GROUP BY s.id, u.name, u.phone
HAVING COUNT(p.price) < COUNT(p.id)
ORDER BY (COUNT(p.id) - COUNT(p.price)), s.created_at
LIMIT $1;

-- name: AdminMarketRankings :many
--
-- the cheapest few shops in every market, in order. It replaced AdminMarketLeaders, which returned
-- only the winner - one row per category said who was cheapest and could not show what the panel is
-- actually for: **whether anybody is competing.** A market where the top three are 4.61, 4.63 and
-- 4.65 million is a fight; one where they are 4.6, 5.4 and 6.2 is one shop with no pressure on it,
-- and the two look identical if you only print the first row.
--
-- `CROSS JOIN LATERAL` and not a window function: sqlc cannot compile a `ROW_NUMBER()` filtered from
-- an outer WHERE (§6), and the lateral is the shape postgres wants anyway - "for each category, the
-- first N of this ordered list". The rank itself is not selected; it is the row's position in the
-- result, which the panel and Go both already have.
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
--
-- what a basket costs in each market right now, and how far apart its shops are. This is the number
-- the founder wants "чтобы примерно понимать" - the one figure that says what a category is worth
-- before any comparison between shops inside it.
--
-- It reads the index view, so **only complete catalogues are in it** (§5): a shop with one unpriced
-- row has no basket and cannot be averaged into one. That is the same rule the badge follows, which
-- is what keeps this number and the app's agreeing.
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
--
-- today's row for every market, written by the hourly job in cmd/api/main.go.
--
-- **The whole statement runs in the database and nothing travels through Go**, which is what makes
-- it safe to run on a timer: it is one aggregate over a view, and the upsert means running it twice
-- an hour or once a day produces exactly the same table.
--
-- A market that has no shops in the comparison writes no row at all rather than a zero - see the
-- migration: a zero here would be a claim that the basket was free.
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
--
-- the last 30 days of every market, oldest first. No generate_series here, unlike AdminSignupsByDay:
-- a missing day is a day the server was not running, and drawing it as a gap is the honest answer
-- where filling it with a zero would draw a market that briefly cost nothing.
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
-- every products.image_path that names an owner's upload, for the orphan sweep.
--
-- filtered in SQL rather than in Go because the catalogue paths outnumber the uploads by two orders
-- of magnitude - one универсальный shop is a hundred rows pointing at photos/universal - and there
-- is no reason to carry them across the wire only to drop them. the prefix is a parameter so
-- imagestore.UploadDir stays the one declaration of what "uploads/" is.
--
-- ::text on the projection, not decoration: image_path is a nullable column, and without the cast
-- sqlc types the result []pgtype.Text and every caller unwraps a wrapper the WHERE clause has
-- already made impossible. same trick as the ::bigint on the counts above.
SELECT image_path::text AS image_path
FROM products
WHERE image_path LIKE @prefix::text;
