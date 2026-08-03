-- a shop now picks a category when it is created, and that choice seeds its catalogue from a fixed
-- template (see internal/catalog/templates.go). locale-neutral codes, translated at the app
-- boundary, matching the convention products.availability already uses - the display names are
-- Универсальный / Сантехника / Дерево / Обои, and adding a language must not need a migration.
-- 'universal' as the default is what keeps this safe for shops that already exist.
ALTER TABLE shops
ADD COLUMN IF NOT EXISTS category VARCHAR(30) NOT NULL DEFAULT 'universal'
    CHECK (category IN ('universal', 'plumbing', 'wood', 'wallpaper'));

-- a seeded product has no price yet - the owner fills it in - and that is not the same fact as
-- "this product costs 0". NULL is exactly the value for "not known", so the column stops claiming
-- a number it doesn't have. existing rows keep whatever they were uploaded with.
ALTER TABLE products
ALTER COLUMN price DROP NOT NULL,
ALTER COLUMN price DROP DEFAULT;

-- which template row this product came from, e.g. 'universal.cement_m400'. NULL means the owner
-- added it themselves (by hand or through the excel upload), so one nullable column carries the
-- whole distinction - a separate source/is_template flag would be a second copy of the same fact
-- and the two could drift out of agreement.
--
-- the unique index is per shop, the same shape as idx_products_shop_article: the same template row
-- exists in every shop of that category, so template_key is only unique alongside shop_id. it makes
-- re-seeding an already-seeded shop fail loudly instead of silently doubling its catalogue.
ALTER TABLE products
ADD COLUMN IF NOT EXISTS template_key VARCHAR(60);

CREATE UNIQUE INDEX IF NOT EXISTS idx_products_shop_template ON products (shop_id, template_key);
