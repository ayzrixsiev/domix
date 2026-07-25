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
