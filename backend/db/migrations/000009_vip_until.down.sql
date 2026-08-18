DROP INDEX IF EXISTS idx_shops_vip_until;

ALTER TABLE shops
ADD COLUMN IF NOT EXISTS is_vip BOOLEAN NOT NULL DEFAULT false;

-- a currently-live placement goes back to true. the expiry date itself cannot be represented in a
-- boolean, so going down is lossy in exactly the way that motivated going up.
UPDATE shops SET is_vip = true WHERE vip_until > CURRENT_TIMESTAMP;

ALTER TABLE shops
DROP COLUMN IF EXISTS vip_until;
