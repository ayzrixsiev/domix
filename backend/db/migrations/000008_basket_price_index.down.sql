DROP INDEX IF EXISTS idx_products_template_priced;

DROP VIEW IF EXISTS shop_basket_index;

-- restored exactly as migration 000007 defined it. both are views over the same `products` rows, so
-- nothing was stored and nothing is lost by going back and forth - the number is recomputed from
-- the prices either way.
CREATE OR REPLACE VIEW shop_average_check AS
SELECT shop_id,
       ROUND(AVG(price))::bigint AS average_check,
       COUNT(*)::bigint          AS priced_products
FROM products
WHERE template_key IS NOT NULL
  AND price IS NOT NULL
GROUP BY shop_id
HAVING COUNT(*) >= 5;
