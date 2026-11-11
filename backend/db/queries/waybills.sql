-- name: CreateWaybill :one
-- the no-op update is what makes a retry answer with the row it already wrote, in one statement
INSERT INTO waybills (user_id, request_id, shop_category, items, photo)
VALUES (@user_id, @request_id, @shop_category, @items::jsonb, @photo)
ON CONFLICT (user_id, request_id) DO UPDATE SET request_id = EXCLUDED.request_id
RETURNING id, shop_category, items, (photo IS NOT NULL)::bool AS has_photo, created_at;

-- name: ListWaybillsOfUser :many
SELECT id, shop_category, items, (photo IS NOT NULL)::bool AS has_photo, created_at
FROM waybills
WHERE user_id = $1
ORDER BY id DESC
LIMIT $2;

-- name: GetWaybillPhotoOfUser :one
-- the user id is in the WHERE, so somebody else's number is the same miss as one that does not exist
SELECT photo FROM waybills WHERE id = $1 AND user_id = $2;

-- name: AdminListWaybills :many
-- no items and no photo: this is the whole inbox, and the rows are read when one is opened
SELECT w.id, w.shop_category, jsonb_array_length(w.items)::int AS item_count,
       (w.photo IS NOT NULL)::bool AS has_photo, w.created_at,
       u.name AS sender_name, u.phone AS sender_phone, u.role AS sender_role
FROM waybills w
JOIN users u ON u.id = w.user_id
ORDER BY w.id DESC
LIMIT $1 OFFSET $2;

-- name: AdminGetWaybill :one
SELECT w.id, w.shop_category, w.items, (w.photo IS NOT NULL)::bool AS has_photo, w.created_at,
       u.name AS sender_name, u.phone AS sender_phone, u.role AS sender_role
FROM waybills w
JOIN users u ON u.id = w.user_id
WHERE w.id = $1;

-- name: AdminGetWaybillPhoto :one
SELECT photo FROM waybills WHERE id = $1;

-- name: AdminDeleteWaybill :execrows
DELETE FROM waybills WHERE id = $1;
