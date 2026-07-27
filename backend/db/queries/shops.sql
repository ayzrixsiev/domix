-- name: CreateShop :one
INSERT INTO shops (user_id, name, contact_phone, image_url, address, location)
VALUES ($1, $2, $3, $4, $5, ST_SetSRID(ST_MakePoint($6, $7), 4326))
RETURNING id, user_id, name, contact_phone, image_url, address, rating, average_paycheck,
          ST_Y(location)::float8 AS latitude, ST_X(location)::float8 AS longitude, created_at, updated_at;

-- name: ListShops :many
SELECT id, user_id, name, contact_phone, image_url, address, rating, average_paycheck,
       ST_Y(location)::float8 AS latitude, ST_X(location)::float8 AS longitude, created_at, updated_at
FROM shops
ORDER BY created_at DESC;

-- name: GetShopOwner :one
-- used to authorize the product upload endpoint: only the shop's own owner (or an admin) may upload
-- products to it, so we need its user_id before trusting a shop_id the client sent us.
SELECT user_id FROM shops WHERE id = $1;

-- name: ListShopsByOwner :many
-- backs GET /api/shops/mine - the "manage my shops" list, as opposed to ListShops above which is
-- the public, unauthenticated list every shop for the map. the product count is what makes that
-- screen useful (an owner needs to see whether an upload actually landed), and a correlated
-- subquery is cheap here since it runs over one owner's handful of shops, not the whole table.
SELECT s.id, s.user_id, s.name, s.contact_phone, s.image_url, s.address, s.rating, s.average_paycheck,
       ST_Y(s.location)::float8 AS latitude, ST_X(s.location)::float8 AS longitude,
       s.created_at, s.updated_at,
       (SELECT COUNT(*) FROM products p WHERE p.shop_id = s.id)::bigint AS product_count
FROM shops s
WHERE s.user_id = $1
ORDER BY s.created_at DESC;
