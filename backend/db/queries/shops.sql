-- name: CreateShop :one
INSERT INTO shops (user_id, name, contact_phone, image_url, address, category, location)
VALUES ($1, $2, $3, $4, $5, $6, ST_SetSRID(ST_MakePoint($7, $8), 4326))
RETURNING id, user_id, name, contact_phone, image_url, address, category, rating,
          COALESCE(vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip,
          ST_Y(location)::float8 AS latitude, ST_X(location)::float8 AS longitude, created_at, updated_at;

-- name: ListShops :many
SELECT s.id, s.user_id, s.name, s.contact_phone, s.image_url, s.address, s.category, s.rating,
       COALESCE(s.vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip,
       ST_Y(s.location)::float8 AS latitude, ST_X(s.location)::float8 AS longitude,
       s.created_at, s.updated_at,
       bi.price_index, bi.basket_price
FROM shops s
LEFT JOIN shop_basket_index bi ON bi.shop_id = s.id
ORDER BY s.created_at DESC;

-- name: GetShopOwner :one
SELECT user_id FROM shops WHERE id = $1;

-- name: UpdateShop :one
WITH updated AS (
    UPDATE shops
    SET name = $2,
        contact_phone = $3,
        address = $4,
        location = ST_SetSRID(ST_MakePoint($5, $6), 4326),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = $1
    RETURNING id, user_id, name, contact_phone, image_url, address, category, rating,
              COALESCE(vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip,
              ST_Y(location)::float8 AS latitude, ST_X(location)::float8 AS longitude,
              created_at, updated_at
)
SELECT u.id, u.user_id, u.name, u.contact_phone, u.image_url, u.address, u.category, u.rating, u.is_vip,
       u.latitude, u.longitude, u.created_at, u.updated_at,
       bi.price_index, bi.basket_price
FROM updated u
LEFT JOIN shop_basket_index bi ON bi.shop_id = u.id;

-- name: SetShopVIP :one
UPDATE shops
SET vip_until = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, vip_until,
          COALESCE(vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip;

-- name: DeleteShop :execrows
DELETE FROM shops WHERE id = $1;

-- name: ListShopsByOwner :many
SELECT s.id, s.user_id, s.name, s.contact_phone, s.image_url, s.address, s.category, s.rating,
       COALESCE(s.vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip,
       ST_Y(s.location)::float8 AS latitude, ST_X(s.location)::float8 AS longitude,
       s.created_at, s.updated_at,
       bi.price_index, bi.basket_price,
       (SELECT COUNT(*) FROM products p WHERE p.shop_id = s.id)::bigint AS product_count
FROM shops s
LEFT JOIN shop_basket_index bi ON bi.shop_id = s.id
WHERE s.user_id = $1
ORDER BY s.created_at DESC;

-- name: ListVipShops :many
SELECT s.id, s.user_id, s.name, s.contact_phone, s.image_url, s.address, s.category, s.rating,
       true AS is_vip,
       ST_Y(s.location)::float8 AS latitude, ST_X(s.location)::float8 AS longitude,
       s.created_at, s.updated_at,
       bi.price_index, bi.basket_price
FROM shops s
JOIN shop_basket_index bi ON bi.shop_id = s.id
WHERE s.vip_until > CURRENT_TIMESTAMP
ORDER BY s.vip_until DESC, s.id ASC
LIMIT $1;

-- name: ListBestOffersInCategory :many
SELECT s.id, s.user_id, s.name, s.contact_phone, s.image_url, s.address, s.category, s.rating,
       COALESCE(s.vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip,
       ST_Y(s.location)::float8 AS latitude, ST_X(s.location)::float8 AS longitude,
       s.created_at, s.updated_at,
       bi.price_index, bi.basket_price
FROM shops s
JOIN shop_basket_index bi ON bi.shop_id = s.id
WHERE s.category = $1
ORDER BY bi.price_index ASC, s.rating DESC
LIMIT $2;
