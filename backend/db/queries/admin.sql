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

-- name: AdminUpdateUser :one
UPDATE users
SET name = $2,
    role = $3,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, phone, role, created_at;

-- name: AdminPriceAnomalies :many
WITH comparable AS (
    SELECT p.id, p.shop_id, p.name, p.template_key, p.price,
           s.category AS shop_category, s.name AS shop_name
    FROM products p
    JOIN shops s ON s.id = p.shop_id
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
SELECT
    COUNT(*)::bigint                                                       AS shops,
    (COUNT(*) FILTER (WHERE priced_rows = 0))::bigint                      AS empty,
    (COUNT(*) FILTER (WHERE pct > 0 AND pct < 50))::bigint                 AS started,
    (COUNT(*) FILTER (WHERE pct >= 50 AND pct < 90))::bigint               AS halfway,
    (COUNT(*) FILTER (WHERE pct >= 90 AND pct < 100))::bigint              AS nearly,
    (COUNT(*) FILTER (WHERE pct >= 100))::bigint                           AS complete,
    (COUNT(*) FILTER (WHERE priced_rows = 0
        AND created_at < CURRENT_TIMESTAMP - INTERVAL '14 days'))::bigint  AS stalled
FROM scored;

-- name: AdminShopsNeedingAttention :many
SELECT s.id,
       s.name,
       s.category,
       s.created_at,
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

-- name: AdminBasketByCategory :many
SELECT s.category,
       COUNT(*)::bigint                                                          AS shops,
       ROUND(AVG(bi.basket_price))::bigint                                       AS mean_basket,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY bi.basket_price)::bigint      AS median_basket,
       MIN(bi.basket_price)::bigint                                              AS min_basket,
       MAX(bi.basket_price)::bigint                                              AS max_basket
FROM shops s
JOIN shop_basket_index bi ON bi.shop_id = s.id
GROUP BY s.category
ORDER BY COUNT(*) DESC, s.category;

-- name: AdminPricingActivity :one
SELECT
    (SELECT COUNT(*) FROM products
      WHERE template_key IS NOT NULL AND price IS NOT NULL
        AND updated_at >= CURRENT_TIMESTAMP - INTERVAL '7 days')::bigint            AS priced_7d,
    (SELECT COUNT(*) FROM products
      WHERE template_key IS NOT NULL AND price IS NOT NULL
        AND updated_at >= CURRENT_TIMESTAMP - INTERVAL '30 days')::bigint           AS priced_30d,
    (SELECT COUNT(DISTINCT shop_id) FROM products
      WHERE template_key IS NOT NULL AND price IS NOT NULL
        AND updated_at >= CURRENT_TIMESTAMP - INTERVAL '7 days')::bigint            AS shops_active_7d;

-- name: AdminVipPlacements :many
SELECT s.id, s.name, s.category, s.vip_until,
       (EXTRACT(EPOCH FROM (s.vip_until - CURRENT_TIMESTAMP)) / 86400)::int AS days_left
FROM shops s
WHERE s.vip_until > CURRENT_TIMESTAMP
ORDER BY s.vip_until
LIMIT $1;
