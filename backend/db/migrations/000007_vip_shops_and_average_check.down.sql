DROP INDEX IF EXISTS idx_products_category_priced;
DROP INDEX IF EXISTS idx_shops_user_id;

DROP VIEW IF EXISTS shop_average_check;

-- restored with its original definition from migration 000001. the values are gone and cannot be
-- recovered, but nothing ever wrote them in the first place - every row held the default - so the
-- default is a faithful restoration rather than a lossy one.
ALTER TABLE shops
ADD COLUMN IF NOT EXISTS average_paycheck INT NOT NULL DEFAULT 0;

ALTER TABLE shops
DROP COLUMN IF EXISTS is_vip;
