-- Products get a photo.
--
-- The founder shot all 99 универсальный products; the optimised files live in /photos/<category>/
-- and the API serves them under /static/products/. This column holds the path *inside* that folder
-- ("universal/001.jpg"), not a full URL: the host changes between the ngrok tunnel, a staging box
-- and production, and a stored absolute URL would be wrong in two of the three. The API prepends
-- the prefix on the way out, the app prepends the host - the same split ApiConfig.serverRoot
-- already uses for everything else.
--
-- Nullable, because a product may genuinely have no photo: the сантехника, древесные and обои
-- templates have no photo set yet, and a product the owner adds themselves has no way to attach one
-- until upload exists.
ALTER TABLE products
ADD COLUMN IF NOT EXISTS image_path VARCHAR(255);
