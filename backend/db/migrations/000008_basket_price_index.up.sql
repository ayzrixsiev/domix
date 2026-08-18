-- The "average check" becomes a Basket Price Index.
--
-- Migration 000007 replaced the dead `shops.average_paycheck` column with a derived average over
-- each shop's priced template products. That fixed the "every shop advertises 0 сум" bug, but the
-- number it produced was still the wrong one to compare shops by:
--
--   * An average answers "what does one item cost here", which is not the question a customer
--     buying a load of materials is asking. They want to know what the whole trip costs.
--
--   * It is not comparable across shop categories. A Обои shop's basket is 10 items and a
--     Универсальный shop's is 50, so ordering "Лучшие предложения" by raw сум ranked shops by which
--     template they happen to be seeded from as much as by price.
--
-- What replaces it is the founder's spec: total the shared basket per shop, average those totals
-- across the market, and express each shop as a percentage of that average.
--
--     Basket Price Index = (this shop's basket / the market's average basket) x 100
--
--     100 = exactly the market price.  < 100 = cheaper than the market.  > 100 = more expensive.
--
-- The index divides сум by сум, so the unit cancels out. That is precisely what makes a 10-item
-- Обои basket and a 50-item Универсальный basket comparable: each is measured against its own
-- market, and what comes out the other side is a pure ratio.

DROP VIEW IF EXISTS shop_average_check;

CREATE OR REPLACE VIEW shop_basket_index AS

-- Step 0, which the founder's worked example takes for granted and real data does not: fill the
-- gaps.
--
-- The example has four stores each with a complete basket, so their totals are directly
-- comparable. In practice an owner prices their fifty seeded products over weeks, and a raw SUM
-- over "whatever is priced so far" is catastrophically wrong - a shop that has priced 3 items has
-- a basket of ~300 000 against a fully-priced neighbour's 5 000 000, and would sit at the top of
-- Лучшие предложения looking ten times cheaper than anyone. That is not a rounding error, it is
-- the ranking inverted: the laziest shop wins.
--
-- So every shop's basket is totalled over the *whole* template, and an item the owner has not
-- priced yet is counted at what that same item costs elsewhere on the market. Every basket then
-- covers the same list of goods, which is the only way two totals mean anything against each
-- other.
--
-- Three properties worth knowing, because they are why this is imputation and not a fudge:
--
--   * For a shop that has priced everything, it is a no-op - there is nothing to substitute, and
--     the result is exactly the founder's arithmetic.
--   * It cannot be gamed. Pricing only the five items you happen to be cheapest on leaves the
--     other forty-five at the market rate, so your index barely moves off 100. The more of your
--     catalogue you price, the more the index is actually about you.
--   * An item nobody anywhere has priced has no market rate to borrow, so it drops out of every
--     shop's basket equally, and the totals stay comparable.
WITH item_market_price AS (
    SELECT template_key,
           AVG(price) AS market_price
    FROM products
    WHERE template_key IS NOT NULL
      AND price IS NOT NULL
    GROUP BY template_key
),

-- Step 1: the basket total per shop.
--
-- Template rows only (`template_key IS NOT NULL`), which is the founder's rule and the reason the
-- comparison holds at all: the template is the shared basket, identical in every shop of a
-- category, so two totals differ only by price. The owner's own added products are unique to their
-- shop - including them would compare a basket of 50 against a basket of 57.
basket AS (
    SELECT p.shop_id,
           s.category                             AS shop_category,
           SUM(COALESCE(p.price, m.market_price)) AS basket_price,
           -- COUNT(expr) counts non-null values, unlike COUNT(*) which counts rows. so these two
           -- are "how many the owner has priced" and "how big the template is".
           COUNT(p.price)                         AS priced_products,
           COUNT(*)                               AS basket_products
    FROM products p
    JOIN shops s                  ON s.id = p.shop_id
    LEFT JOIN item_market_price m ON m.template_key = p.template_key
    WHERE p.template_key IS NOT NULL
    GROUP BY p.shop_id, s.category
),

-- A shop has to have done enough work to be quoted.
--
-- Imputation means a shop that priced nothing gets a basket made entirely of market rates - an
-- index of exactly 100, which is a confident-looking claim backed by no data at all. The floor is
-- what stops that.
--
-- A percentage rather than a fixed count, because the templates are different sizes: 30% is 15
-- items of a Универсальный basket and 3 of a Обои one, which is the same commitment from each
-- owner. Integer arithmetic on both sides, so there is no float rounding to reason about.
--
-- Below the floor the shop simply has no row here, which the LEFT JOIN in db/queries/shops.sql
-- turns into NULL - "not enough data yet", carried all the way to the app as a null rather than as
-- a misleading 100.
qualified AS (
    SELECT *
    FROM basket
    WHERE priced_products * 100 >= basket_products * 30
      AND basket_price IS NOT NULL
),

-- Step 2: the market's average basket.
--
-- Grouped by shop category, and that grouping is the whole reason the index is comparable. Each
-- shop is measured against the shops it is actually in competition with - a Сантехника shop
-- against other Сантехника shops - so what the index reports is "cheaper than my market", not
-- "sells fewer things than the shop down the road".
--
-- Only qualified shops feed the average, so a shop that hasn't priced enough to be ranked also
-- cannot drag the baseline around with its half-empty basket.
market AS (
    SELECT shop_category,
           AVG(basket_price) AS market_basket
    FROM qualified
    GROUP BY shop_category
)

-- Step 3: the index itself.
--
-- Note what happens with a single shop in a category: it *is* the market average, so it scores
-- exactly 100. That is correct rather than a degenerate case - with nobody to compare against,
-- "average" is the only honest answer - but it is worth recognising when the first shop of a new
-- category appears and reads 100 forever until a second one arrives.
SELECT q.shop_id,
       ROUND(q.basket_price)::bigint                         AS basket_price,
       ROUND(q.basket_price / m.market_basket * 100)::bigint AS price_index,
       q.priced_products,
       q.basket_products
FROM qualified q
JOIN market m ON m.shop_category = q.shop_category
-- division guard. unreachable while prices are positive, but a view that can raise
-- division_by_zero takes down every query that touches it, including the map.
WHERE m.market_basket > 0;

-- the item_market_price CTE groups every priced template row by template_key, which is a different
-- access path from the existing unique index on (shop_id, template_key) - that one is ordered by
-- shop first, so it cannot answer "all rows for this template item" without scanning. partial,
-- because an unpriced row can never contribute to a market price.
CREATE INDEX IF NOT EXISTS idx_products_template_priced
    ON products (template_key, price)
    WHERE template_key IS NOT NULL AND price IS NOT NULL;
