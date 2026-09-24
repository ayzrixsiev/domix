-- Every stored image path gains the `shops/` prefix, so one images root can hold more than products.
--
-- On disk that root is `images/`, and `images/shops/` is what used to be `photos/`. Paths are stored
-- relative to the root and never as a full url, so this one statement is the whole rename - the
-- served address and the R2 object key both follow from it.
UPDATE product_templates SET image_path = 'shops/' || image_path
WHERE image_path IS NOT NULL AND image_path NOT LIKE 'shops/%';

UPDATE products SET image_path = 'shops/' || image_path
WHERE image_path IS NOT NULL AND image_path NOT LIKE 'shops/%';
