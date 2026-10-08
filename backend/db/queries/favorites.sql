-- name: ListFavorites :many
-- The same columns ListProductsByCategory selects, in the same order, so both convert to one row
-- type and the app renders them with the grid it already has.
SELECT p.id, p.shop_id, p.name, p.specs, p.price, p.category, p.unit, p.availability, p.template_key,
       p.image_path, s.name AS shop_name
FROM favorites f
JOIN products p ON p.id = f.product_id
JOIN shops s ON s.id = p.shop_id
WHERE f.user_id = $1
ORDER BY f.created_at DESC, f.product_id
LIMIT $2;

-- name: AddFavorite :exec
-- idempotent: the app toggles optimistically, so a retry after a dropped answer must not be an error
INSERT INTO favorites (user_id, product_id)
VALUES ($1, $2)
ON CONFLICT (user_id, product_id) DO NOTHING;

-- name: RemoveFavorite :exec
DELETE FROM favorites WHERE user_id = $1 AND product_id = $2;
