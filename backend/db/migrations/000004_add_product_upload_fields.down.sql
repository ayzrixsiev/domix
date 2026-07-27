DROP INDEX IF EXISTS idx_products_shop_article;
ALTER TABLE products
DROP COLUMN IF EXISTS unit,
DROP COLUMN IF EXISTS availability,
DROP COLUMN IF EXISTS article;
