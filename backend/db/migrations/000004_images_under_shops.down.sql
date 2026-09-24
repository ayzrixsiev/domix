UPDATE product_templates SET image_path = substring(image_path from 7)
WHERE image_path LIKE 'shops/%';

UPDATE products SET image_path = substring(image_path from 7)
WHERE image_path LIKE 'shops/%';
