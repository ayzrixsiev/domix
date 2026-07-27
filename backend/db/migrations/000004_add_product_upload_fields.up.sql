-- fields needed for the bulk excel upload (see db/queries/products.sql UpsertProduct): unit of
-- measurement (шт/кг/м² etc), a locale-neutral availability status (translated at the app boundary
-- from the excel file's "Есть/Под заказ/Нет" column so ru/uz display text can be added later without
-- a migration), and article (SKU). defaults keep this a safe migration if products already exist,
-- matching the shops.contact_phone migration above.
ALTER TABLE products
ADD COLUMN IF NOT EXISTS unit VARCHAR(20) NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS availability VARCHAR(20) NOT NULL DEFAULT 'in_stock'
    CHECK (availability IN ('in_stock', 'on_order', 'unavailable')),
ADD COLUMN IF NOT EXISTS article VARCHAR(100);

-- a product's natural key is (shop_id, article), not article alone - the same article can be reused
-- by different shops. this is what lets re-uploading the same file update existing rows instead of
-- creating duplicates (see UpsertProduct's ON CONFLICT). postgres treats NULL as distinct from every
-- other value in a unique index, so hand-added products with no article (a later, non-bulk-upload
-- feature) are simply never deduped by this constraint.
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_shop_article ON products (shop_id, article);
