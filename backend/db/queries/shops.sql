-- Two things repeat in almost every query in this file, so read them once here.
--
-- `COALESCE(s.vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip` - the app is only ever
-- asking "badge this shop or not", so the wire keeps the boolean it always had and the date stays a
-- backend concern. it is computed rather than stored: a stored flag would need something to come
-- along and switch it off when the placement lapsed, and there is no such thing (see migration
-- 000009).
--
-- both wrappers earn their place. COALESCE, because a shop that never held a placement has
-- vip_until = NULL and `NULL > anything` is NULL, not false - which would reach the app as a null
-- where it expects a bool. and the ::boolean cast, because sqlc cannot infer a type through a bare
-- COALESCE and generated the field as `interface{}`, pushing a runtime type assertion into the one
-- layer whose whole job is to be checked at compile time.
--
-- `LEFT JOIN shop_basket_index bi` - the Basket Price Index (migration 000008, tightened by 000013).
-- LEFT, because the view only holds shops that have priced their *whole* template, and a shop still
-- working through its prices is a normal state rather than a missing shop. the columns come back
-- NULL and the app renders no number rather than a wrong one. expect that to be the majority of
-- shops early on: one unpriced row is enough to keep a shop out.

-- name: CreateShop :one
-- the basket index is deliberately absent from the RETURNING list, unlike every other query here.
-- this statement runs *before* the category template has even been seeded into products, so any
-- join could only return NULL. the handler sends null for it, which is the truth: a shop created
-- one millisecond ago has priced nothing.
INSERT INTO shops (user_id, name, contact_phone, image_url, address, category, location)
VALUES ($1, $2, $3, $4, $5, $6, ST_SetSRID(ST_MakePoint($7, $8), 4326))
RETURNING id, user_id, name, contact_phone, image_url, address, category, rating,
          COALESCE(vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip,
          ST_Y(location)::float8 AS latitude, ST_X(location)::float8 AS longitude, created_at, updated_at;

-- name: ListShops :many
-- every shop, for the map's pins. LEFT JOIN and not INNER, and this is the query where that matters
-- most: a shop with an incomplete basket is deliberately still a pin on the map - a real business at
-- a real address - it just carries no price label above it.
SELECT s.id, s.user_id, s.name, s.contact_phone, s.image_url, s.address, s.category, s.rating,
       COALESCE(s.vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip,
       ST_Y(s.location)::float8 AS latitude, ST_X(s.location)::float8 AS longitude,
       s.created_at, s.updated_at,
       bi.price_index, bi.basket_price
FROM shops s
LEFT JOIN shop_basket_index bi ON bi.shop_id = s.id
ORDER BY s.created_at DESC;

-- name: GetShopOwner :one
-- used to authorize the shop and product mutation endpoints: only the shop's own owner (or
-- an admin) may touch it, so we need its user_id before trusting a shop_id the client sent us.
SELECT user_id FROM shops WHERE id = $1;

-- name: UpdateShop :one
-- backs PUT /api/shops/{id} - the "edit shop" form, which always submits all four editable fields,
-- so this is a full replacement rather than a per-column patch. image_url is deliberately absent:
-- photos aren't uploadable yet, and listing the column here would blank it once they are. category
-- is absent for a different reason: it decided which template seeded this shop's catalogue, so
-- changing it later would leave the shop stocked with the wrong list. vip_until is absent because
-- it is a paid placement - the owner does not get to grant it to themselves through the edit form,
-- which is why it has its own admin-only endpoint. updated_at is set by hand because there is no
-- trigger on this table (see db/migrations/000001).
--
-- the index has to come back too, or an edited shop would lose its price label on the map until the
-- next full reload - the same problem product_count has, which the app patches by hand.
--
-- it is fetched by wrapping the UPDATE in a CTE and selecting from it, rather than by putting a
-- scalar subquery in the RETURNING list. both are valid postgres and both return the same value;
-- the difference is what sqlc infers. a subquery in RETURNING was generated as a non-nullable
-- `int64`, which would have panicked the first time an owner edited a shop with an incomplete basket
-- - the overwhelmingly common case - because pgx cannot scan NULL into an int64. an explicit LEFT
-- JOIN says "this may be absent" in a way the generator reads correctly, so the type follows from
-- the query's own shape instead of from a hand-written override that could drift.
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
-- backs PUT /api/admin/shops/{id}/vip - granting or revoking a paid placement.
--
-- one statement for both, because they are the same fact with different values: a date grants until
-- that date, NULL revokes. a separate DELETE endpoint would be a second thing to keep in step with
-- the first for no gain.
--
-- it returns the whole shop rather than just the flag so the caller can confirm what it actually
-- set, and so an admin tool can render the updated row without a second read.
UPDATE shops
SET vip_until = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, vip_until,
          COALESCE(vip_until > CURRENT_TIMESTAMP, false)::boolean AS is_vip;

-- name: DeleteShop :execrows
-- the shop's products go with it via products.shop_id ON DELETE CASCADE (db/migrations/000001), so
-- there is nothing to clean up first. :execrows returns the number of rows deleted, which is how the
-- handler tells "already gone" apart from "deleted just now".
DELETE FROM shops WHERE id = $1;

-- name: ListShopsByOwner :many
-- backs GET /api/shops/mine - the "manage my shops" list, as opposed to ListShops above which is
-- the public, unauthenticated list of every shop for the map. the product count is what makes that
-- screen useful (an owner needs to see how much of their catalogue exists), and a correlated
-- subquery is cheap here since it runs over one owner's handful of shops, not the whole table.
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
-- the home screen's "VIP Магазины" carousel: shops holding a live paid placement.
--
-- `vip_until > CURRENT_TIMESTAMP` and not `vip_until IS NOT NULL` - an expired placement is a
-- placement that ended, and the whole reason 000009 made this a date was so that ending happens on
-- its own. a lapsed shop drops out of the carousel on the next request with nobody involved.
--
-- INNER JOIN on the index, unlike ListShops above: this is a shop-window, and a card with a blank
-- where its price comparison should be is not worth the slot someone paid for.
--
-- **the order is not a ranking, and rating is deliberately not in it.** membership in this carousel
-- is sold: whoever pays gets placed by hand, and nothing the shop does earns or loses a position. it
-- used to read `ORDER BY s.rating DESC`, which was both a lie about how the slot is decided and
-- inert in practice - shops.rating is a column nothing writes, so every shop scored 0.0 and the
-- "ranking" silently fell through to created_at.
--
-- `vip_until DESC` is the closest thing to an honest order available without inventing a column: the
-- placement running longest shows first, which for equal-length placements means the most recently
-- granted. if the order ever needs to be chosen by hand, that is a `vip_rank` column, not a proxy.
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
-- the home screen's "Лучшие предложения": the cheapest N shops of one shop category. the section is
-- a tab strip - Универсальный / Сантехника / Дерево / Обои - and the handler calls this once per
-- category so that switching a tab is not a network request.
--
-- **one call per category, and not one window-function query for all four.** the natural way to
-- write "top N per group" is `ROW_NUMBER() OVER (PARTITION BY s.category ORDER BY bi.price_index)`
-- filtered on the rank, and it was written that way first. sqlc cannot compile it: the rank has to
-- be referenced from an outer WHERE (a window function is computed after WHERE runs, so it cannot
-- filter itself), and sqlc's analyzer does not carry an alias out of a derived table or a CTE -
-- `column "category_rank" does not exist`. rather than contort the SQL around the generator, the
-- grouping moved into Go, where it is a four-iteration loop over catalog.AllShopCategories. the cost
-- is three extra round trips on one endpoint; the benefit is a query anyone can read.
--
-- ranking by price_index and not by basket_price is the point of the index existing. within one tab
-- the two would agree - one tab is one template, so the totals are comparable - but the badge the
-- app renders is derived from the index, and ranking by anything else would order the list
-- differently from the labels printed on it.
--
-- there is no location input here and that is deliberate: this section replaced a "магазины рядом"
-- list, and a shop qualifies on price wherever it is. VIP shops are not excluded either - VIP is a
-- placement tier, not a separate catalogue, so a VIP shop that is genuinely cheap earns a row the
-- same as anyone.
--
-- the JOIN is an inner one, and here it is load-bearing rather than cosmetic: a shop with no
-- published index has nothing to be ranked by, and a LEFT JOIN would sort those NULLs to one end of
-- a list whose entire meaning is the ordering.
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
