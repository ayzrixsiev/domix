-- contact number shown on the shop's card; default '' so this stays a safe migration if shops already exist
ALTER TABLE shops
ADD COLUMN IF NOT EXISTS contact_phone VARCHAR(50) NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS image_url VARCHAR(255);
