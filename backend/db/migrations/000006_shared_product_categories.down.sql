-- restores the excel upload's dedupe key. NULL for every existing row, which is exactly the state
-- a shop that never uploaded a spreadsheet was in anyway - postgres treats NULLs as distinct in a
-- unique index, so the index below accepts all of them.
ALTER TABLE products
ADD COLUMN IF NOT EXISTS article VARCHAR(100);

CREATE UNIQUE INDEX IF NOT EXISTS idx_products_shop_article ON products (shop_id, article);

-- products.category is deliberately left holding the new codes. reverting it would mean pinning a
-- copy of the old russian template list inside this file, which would then be a second source of
-- truth for something internal/catalog already owns - and unlike migration 000005's price fix,
-- nothing here is a constraint that refuses to apply until the data is changed back.
