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
--
-- the paid placements, newest-expiring first. **a LEFT JOIN, deliberately.**
--
-- it was an INNER JOIN, which meant a placement that had been granted and paid for did not appear
-- in the carousel until its owner had priced every last template row - silently, with nothing
-- anywhere saying why. that is the worst failure this endpoint has: somebody paid and sees nothing.
-- the map's ListShops has always left-joined the same view for the same reason, and basket_price /
-- price_tier are nullable end to end precisely so a card can render without them (§5). a VIP card
-- with no price is a shop with no comparison yet; a missing VIP card is a refund.
--
-- the ORDER BY is the *sale*, not a tidy-up. the carousel opens on the first row of this list and
-- fills outwards from it (see VipShopsCarousel), so row one is the centre slot - the most valuable
-- position in the section. `vip_until DESC` gives it to the placement with the longest run still
-- ahead of it, which is the one thing about a placement the database actually knows: it rewards the
-- bigger purchase, and a renewal moves a shop back to the middle. it is also *stable* - a customer
-- refreshing the home screen sees the same order, and the founder can tell an owner exactly what
-- they bought. rotating the centre per request was the alternative and was rejected on that second
-- point: a slot nobody can describe is a slot that is hard to sell.
--
-- `s.id ASC` makes the order total, so two placements bought for the same day do not swap places
-- between requests.
SELECT s.id, s.user_id, s.name, s.contact_phone, s.image_url, s.address, s.category, s.rating,
       true AS is_vip,
       ST_Y(s.location)::float8 AS latitude, ST_X(s.location)::float8 AS longitude,
       s.created_at, s.updated_at,
       bi.price_index, bi.basket_price
FROM shops s
LEFT JOIN shop_basket_index bi ON bi.shop_id = s.id
WHERE s.vip_until > CURRENT_TIMESTAMP
ORDER BY s.vip_until DESC, s.id ASC
LIMIT $1;

-- name: ListBestOffersInCategory :many
--
-- one tab of "Лучшие предложения": the cheapest shops in one shop category, cheapest first.
--
-- **an INNER JOIN here, unlike ListVipShops above, and the difference is the point of each list.**
-- this one *is* the price ranking - a shop with no basket has no place in an ordering by price, and
-- padding it in with a null would put an unpriced shop at one end of a list whose whole meaning is
-- which end you are at. the VIP carousel ranks nothing; it shows what was bought.
--
-- ORDER BY price_index, not basket_price, and inside a single shop category the two are the *same
-- ordering*: the index is `basket ÷ that category's average basket`, and the divisor is one constant
-- for every row this WHERE lets through, so dividing by it cannot reorder anything. the index is used
-- because the view already carries it. pinned by TestBestOffersRankByPriceWhicheverNumberYouUse.
--
-- s.rating DESC is the tie-break and does nothing today - nothing writes shops.rating (§6) - which
-- is why it is second and not first. two shops with identical baskets are genuinely tied on the
-- question this section asks, and a rating is the next thing a customer would use.
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
