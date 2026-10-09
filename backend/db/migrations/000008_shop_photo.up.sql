-- the storefront photograph a VIP card shows on the home screen.
--
-- **an upload, never a curated file**: one shop's own building, so the path lands under
-- `shops/uploads/` like a product photo and is covered by the same deletion door (imagestore.IsUpload)
-- and the same orphan sweep. nullable rather than '' because "no photo" and "a photo" are the only
-- two states, and a NULL cannot be mistaken for a path.
ALTER TABLE shops ADD COLUMN image_path TEXT;
