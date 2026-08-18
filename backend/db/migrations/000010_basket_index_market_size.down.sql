-- back to the 000008 definition, without market_size.
--
-- a plain CREATE OR REPLACE cannot *drop* a column, only add one, so the view has to be dropped and
-- rebuilt. nothing is lost by that - it holds no data, it is a query with a name.
DROP VIEW IF EXISTS shop_basket_index;

CREATE VIEW shop_basket_index AS
WITH item_market_price AS (
    SELECT template_key,
           AVG(price) AS market_price
    FROM products
    WHERE template_key IS NOT NULL
      AND price IS NOT NULL
    GROUP BY template_key
),
basket AS (
    SELECT p.shop_id,
           s.category                             AS shop_category,
           SUM(COALESCE(p.price, m.market_price)) AS basket_price,
           COUNT(p.price)                         AS priced_products,
           COUNT(*)                               AS basket_products
    FROM products p
    JOIN shops s                  ON s.id = p.shop_id
    LEFT JOIN item_market_price m ON m.template_key = p.template_key
    WHERE p.template_key IS NOT NULL
    GROUP BY p.shop_id, s.category
),
qualified AS (
    SELECT *
    FROM basket
    WHERE priced_products * 100 >= basket_products * 30
      AND basket_price IS NOT NULL
),
market AS (
    SELECT shop_category,
           AVG(basket_price) AS market_basket
    FROM qualified
    GROUP BY shop_category
)
SELECT q.shop_id,
       ROUND(q.basket_price)::bigint                         AS basket_price,
       ROUND(q.basket_price / m.market_basket * 100)::bigint AS price_index,
       q.priced_products,
       q.basket_products
FROM qualified q
JOIN market m ON m.shop_category = q.shop_category
WHERE m.market_basket > 0;
