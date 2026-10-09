-- the files themselves stay on disk; the uploads sweep collects them once no row names them
ALTER TABLE shops DROP COLUMN IF EXISTS image_path;
