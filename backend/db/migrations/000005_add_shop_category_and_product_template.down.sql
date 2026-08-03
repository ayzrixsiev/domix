DROP INDEX IF EXISTS idx_products_shop_template;

ALTER TABLE products
DROP COLUMN IF EXISTS template_key;

-- going back to NOT NULL needs every NULL price filled first, or the constraint is rejected
UPDATE products SET price = 0 WHERE price IS NULL;

ALTER TABLE products
ALTER COLUMN price SET DEFAULT 0,
ALTER COLUMN price SET NOT NULL;

ALTER TABLE shops
DROP COLUMN IF EXISTS category;
