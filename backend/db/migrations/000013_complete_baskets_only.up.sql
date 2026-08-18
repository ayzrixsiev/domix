-- Only a shop that has priced its *entire* template gets an index.
--
-- Until now the view accepted a shop at 30% priced and filled the missing rows in at whatever the
-- same item costs elsewhere (imputation). Both of those go, and they go together, because they were
-- one idea: "let a half-finished shop be ranked anyway, on borrowed numbers".
--
-- The founder's rule replaces it: a shop that has not priced every product in its shared basket is
-- not an active shop. It stays on the map - it is a real business at a real address with a real
-- phone number - but it publishes no basket total, no comparison and no badge, and it does not
-- count toward anybody else's market average either. One unpriced row is enough.
--
-- What that buys, and it is worth being precise because the old rule was defensible too:
--
--   * Every quoted basket is now made entirely of prices the shop's own owner typed. Under
--     imputation, a shop at the floor was quoting a basket that was 70% other people's prices while
--     the badge said "на 4% дешевле рынка" - a claim about *this* shop built mostly out of other
--     shops.
--   * The market average is an average of complete baskets, so the baseline every badge is measured
--     against is made of the same material as the baskets being measured.
--   * The rule is explicable to a shop owner in one sentence, which the 30%-plus-imputation rule was
--     not. "Укажите все цены" is a thing somebody can do; "price at least 30% and we will guess the
--     rest at market rate" is a thing somebody has to be taught.
--
-- What it costs, and this is the real trade: far fewer shops will carry a badge, especially in the
-- first weeks. A Универсальный owner has 99 prices to type before their shop appears in Лучшие
-- предложения at all. That is the intended pressure - it is what makes the number mean something -
-- but it does mean the home screen will look thin until owners finish, and the frontend has to tell
-- an owner where they stand (ShopProductsScreen's progress card).
--
-- Note the one thing that has NOT changed: a lone shop in a category is still its own market and
-- still scores exactly 100. Correct, since there is nothing to be cheaper than, and still looks like
-- a bug the first time you see it.

DROP VIEW IF EXISTS shop_basket_index;

CREATE VIEW shop_basket_index AS

-- Step 1: the basket total per shop, over template rows only.
--
-- `template_key IS NOT NULL` is what makes two totals comparable at all: the template is the shared
-- basket, identical in every shop of a category, so two totals differ only by price. The owner's own
-- products are unique to their shop - including them would compare a basket of 99 against one of
-- 106.
--
-- COUNT(price) counts non-null values where COUNT(*) counts rows, so the pair is "how many the owner
-- has priced" against "how big the basket is". Equality between them is the whole rule, and it is
-- expressed as a count comparison rather than as `bool_and(price IS NOT NULL)` only because the
-- number is worth having in the HAVING clause where a reader can see what is being required.
WITH basket AS (
    SELECT p.shop_id,
           s.category     AS shop_category,
           SUM(p.price)   AS basket_price,
           COUNT(*)       AS basket_products
    FROM products p
    JOIN shops s ON s.id = p.shop_id
    WHERE p.template_key IS NOT NULL
    GROUP BY p.shop_id, s.category
    HAVING COUNT(p.price) = COUNT(*)
),

-- Step 2: the market's average basket, per shop category.
--
-- The grouping is what makes the index comparable: each shop is measured against the shops it
-- actually competes with. A Сантехника basket is a different list of goods from a Универсальный one,
-- so averaging them together would report "sells fewer things than the shop down the road" as
-- "cheaper".
--
-- It reads from `basket`, which by now contains complete baskets only - so an owner halfway through
-- typing prices cannot drag the baseline around, in either direction.
market AS (
    SELECT shop_category,
           AVG(basket_price) AS market_basket
    FROM basket
    GROUP BY shop_category
)

-- Step 3: the index. 100 is the market price, 96 is four percent cheaper, 106 six percent dearer.
SELECT b.shop_id,
       b.basket_price::bigint                                AS basket_price,
       ROUND(b.basket_price / m.market_basket * 100)::bigint AS price_index,
       b.basket_products
FROM basket b
JOIN market m ON m.shop_category = b.shop_category
-- division guard. unreachable while prices are positive, but a view that can raise
-- division_by_zero takes down every query that touches it, including the map.
WHERE m.market_basket > 0;

-- idx_products_template_priced existed for one thing only: the item_market_price CTE, which grouped
-- every priced row in the database by template_key to compute what to impute with. Nothing groups by
-- template_key any more - the view now reads one shop's rows at a time, which the existing unique
-- index on (shop_id, template_key) already serves - so this is dead weight on every product insert
-- and every price edit.
DROP INDEX IF EXISTS idx_products_template_priced;
