-- Make name nullable in case they share contact without a set name
ALTER TABLE users ALTER COLUMN name DROP NOT NULL;

-- Add Telegram chat ID and Role with strict database-level constraints
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS telegram_chat_id BIGINT UNIQUE,
ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'customer' 
CHECK (role IN ('customer', 'shop_owner', 'admin'));