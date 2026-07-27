-- name: UpsertProduct :exec
-- a product's natural key is (shop_id, article) - see migration 000004. re-running this with an
-- article already on file for this shop updates that row instead of creating a duplicate.
INSERT INTO products (shop_id, name, price, category, unit, availability, article)
VALUES ($1, $2, $3, $4, $5, $6, $7)
ON CONFLICT (shop_id, article) DO UPDATE
SET name = EXCLUDED.name,
    price = EXCLUDED.price,
    category = EXCLUDED.category,
    unit = EXCLUDED.unit,
    availability = EXCLUDED.availability,
    updated_at = CURRENT_TIMESTAMP;
