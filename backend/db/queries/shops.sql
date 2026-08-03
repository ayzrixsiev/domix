-- name: CreateShop :one
INSERT INTO shops (user_id, name, contact_phone, image_url, address, category, location)
VALUES ($1, $2, $3, $4, $5, $6, ST_SetSRID(ST_MakePoint($7, $8), 4326))
RETURNING id, user_id, name, contact_phone, image_url, address, category, rating, average_paycheck,
          ST_Y(location)::float8 AS latitude, ST_X(location)::float8 AS longitude, created_at, updated_at;

-- name: ListShops :many
SELECT id, user_id, name, contact_phone, image_url, address, category, rating, average_paycheck,
       ST_Y(location)::float8 AS latitude, ST_X(location)::float8 AS longitude, created_at, updated_at
FROM shops
ORDER BY created_at DESC;

-- name: GetShopOwner :one
-- used to authorize the shop and product mutation endpoints: only the shop's own owner (or
-- an admin) may touch it, so we need its user_id before trusting a shop_id the client sent us.
SELECT user_id FROM shops WHERE id = $1;

-- name: UpdateShop :one
-- backs PUT /api/shops/{id} - the "edit shop" form, which always submits all four editable fields,
-- so this is a full replacement rather than a per-column patch. image_url is deliberately absent:
-- photos aren't uploadable yet, and listing the column here would blank it once they are. category
-- is absent for a different reason: it decided which template seeded this shop's catalogue, so
-- changing it later would leave the shop stocked with the wrong list.
-- updated_at is set by hand because there is no trigger on this table (see db/migrations/000001).
UPDATE shops
SET name = $2,
    contact_phone = $3,
    address = $4,
    location = ST_SetSRID(ST_MakePoint($5, $6), 4326),
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, user_id, name, contact_phone, image_url, address, category, rating, average_paycheck,
          ST_Y(location)::float8 AS latitude, ST_X(location)::float8 AS longitude, created_at, updated_at;

-- name: DeleteShop :execrows
-- the shop's products go with it via products.shop_id ON DELETE CASCADE (db/migrations/000001), so
-- there is nothing to clean up first. :execrows returns the number of rows deleted, which is how the
-- handler tells "already gone" apart from "deleted just now".
DELETE FROM shops WHERE id = $1;

-- name: ListShopsByOwner :many
-- backs GET /api/shops/mine - the "manage my shops" list, as opposed to ListShops above which is
-- the public, unauthenticated list every shop for the map. the product count is what makes that
-- screen useful (an owner needs to see how much of their catalogue exists), and a correlated
-- subquery is cheap here since it runs over one owner's handful of shops, not the whole table.
SELECT s.id, s.user_id, s.name, s.contact_phone, s.image_url, s.address, s.category, s.rating, s.average_paycheck,
       ST_Y(s.location)::float8 AS latitude, ST_X(s.location)::float8 AS longitude,
       s.created_at, s.updated_at,
       (SELECT COUNT(*) FROM products p WHERE p.shop_id = s.id)::bigint AS product_count
FROM shops s
WHERE s.user_id = $1
ORDER BY s.created_at DESC;
