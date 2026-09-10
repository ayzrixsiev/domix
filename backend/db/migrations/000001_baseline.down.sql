DROP TRIGGER IF EXISTS products_basket_index_truncate ON products;
DROP TRIGGER IF EXISTS shops_basket_index_excluded ON shops;
DROP TRIGGER IF EXISTS shops_basket_index_delete ON shops;
DROP TRIGGER IF EXISTS products_basket_index_update ON products;
DROP TRIGGER IF EXISTS products_basket_index_delete ON products;
DROP TRIGGER IF EXISTS products_basket_index_insert ON products;

DROP FUNCTION IF EXISTS basket_index_refresh_all();
DROP FUNCTION IF EXISTS basket_index_after_product_update();
DROP FUNCTION IF EXISTS basket_index_after_products();
DROP FUNCTION IF EXISTS refresh_basket_index(text);

DROP TABLE IF EXISTS shop_basket_index;
DROP TABLE IF EXISTS basket_history;
DROP TABLE IF EXISTS support_thread_reads;
DROP TABLE IF EXISTS support_messages;
DROP TABLE IF EXISTS product_templates;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS shops;
DROP TABLE IF EXISTS users;
