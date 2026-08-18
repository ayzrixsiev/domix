-- the three sections of the home screen stop being hardcoded flutter lists and start reading this
-- database. two of them need something the schema does not have yet.

-- 1. VIP placement.
--
-- "VIP Магазины" is a *paid* tier, so it cannot be derived from anything - no query over ratings or
-- prices could compute "this owner bought a placement". it has to be a stored fact, and a boolean is
-- the whole of it for now. when placements gain a paid-until date this becomes a timestamp and the
-- flag becomes `vip_until > now()`; a boolean is the honest shape while there is no billing.
ALTER TABLE shops
ADD COLUMN IF NOT EXISTS is_vip BOOLEAN NOT NULL DEFAULT false;

-- 2. The average check.
--
-- shops.average_paycheck has existed since migration 000001 as `INT NOT NULL DEFAULT 0` and nothing
-- has ever written to it, so every real shop has been advertising "0 сум" as its average check - the
-- one number the map-first pitch is built on. it is dropped here rather than backfilled, for the same
-- reason products.article was dropped in 000006: a column no code path fills is a trap for whoever
-- reads the schema next.
--
-- what replaces it is derived, because it is derivable: the prices are already in `products`, and a
-- stored copy would be a second source of truth that goes stale on every price edit.
ALTER TABLE shops
DROP COLUMN IF EXISTS average_paycheck;

-- the derivation, defined once here rather than pasted into the six queries that need it.
--
-- three decisions worth keeping:
--
--   * template rows only (`template_key IS NOT NULL`). the template is the shared basket - every
--     shop of a category holds exactly the same rows - which is the entire reason two shops'
--     averages can be compared at all. the owner's own products are unique to their shop, so
--     including them would let one shop drag its average down by stocking a cheap item nobody else
--     carries.
--
--   * priced rows only (`price IS NOT NULL`). NULL means "the owner hasn't got to this one yet",
--     which is not the same fact as "this is free" - the distinction migration 000005 introduced and
--     the whole seeded-catalogue workflow depends on. counting an unpriced row as 0 would make an
--     untouched shop the cheapest in the country.
--
--   * a floor of 5 priced rows. one bag of nails at 5 000 сум is not an average check, and without
--     this a shop that priced a single cheap item would top "Лучшие предложения" over a shop that
--     honestly priced all fifty. below the floor the shop has no row here at all, which the LEFT JOIN
--     in the queries turns into NULL - "not enough data yet", carried all the way to the app as a
--     null rather than a zero.
--
-- AVG and not SUM: a full-basket sum is the number the pitch really wants, but it is only comparable
-- once every shop has priced every row, and partial pricing is the normal state. an average over
-- whatever is priced degrades gracefully; a sum silently rewards the shop that priced the least.
CREATE OR REPLACE VIEW shop_average_check AS
SELECT shop_id,
       ROUND(AVG(price))::bigint AS average_check,
       COUNT(*)::bigint          AS priced_products
FROM products
WHERE template_key IS NOT NULL
  AND price IS NOT NULL
GROUP BY shop_id
HAVING COUNT(*) >= 5;

-- 3. Indexes for the two access patterns this adds, plus one that was always missing.
--
-- postgres does not index a foreign key automatically. every "my shops" load filters on user_id, and
-- deleting a user cascades through the same column, so both have been sequential scans.
CREATE INDEX IF NOT EXISTS idx_shops_user_id ON shops (user_id);

-- the home screen's category counts group every priced product by category, and the category
-- drill-down filters on it. partial, because an unpriced row can never satisfy either query - which
-- on a fresh shop is 50 rows out of 50, so the index stays small exactly when the table is mostly
-- placeholder.
CREATE INDEX IF NOT EXISTS idx_products_category_priced
    ON products (category, shop_id)
    WHERE price IS NOT NULL;
