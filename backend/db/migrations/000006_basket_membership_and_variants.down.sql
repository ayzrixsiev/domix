-- back to "every template row is the basket", and to one photo file per template row.
--
-- the photos are restored by key, which is the only reason this migration is reversible: the files
-- themselves were never deleted here. if the admin panel's catalogue sweep has since removed them,
-- rolling back leaves those rows pointing at files that are gone.

UPDATE product_templates SET image_path = 'shops/universal/002.jpg' WHERE template_key = 'universal.tape_45x40';
UPDATE product_templates SET image_path = 'shops/universal/013.jpg' WHERE template_key = 'universal.spatula_400';
UPDATE product_templates SET image_path = 'shops/universal/021.jpg' WHERE template_key = 'universal.grinding_disc_1000';
UPDATE product_templates SET image_path = 'shops/universal/022.jpg' WHERE template_key = 'universal.grinding_disc_1500';
UPDATE product_templates SET image_path = 'shops/universal/026.jpg' WHERE template_key = 'universal.sds_drill_10x350';
UPDATE product_templates SET image_path = 'shops/universal/029.jpg' WHERE template_key = 'universal.tape_measure_10m';
UPDATE product_templates SET image_path = 'shops/universal/038.jpg' WHERE template_key = 'universal.led_lamp_60w';
UPDATE product_templates SET image_path = 'shops/universal/047.jpg' WHERE template_key = 'universal.brush_4';
UPDATE product_templates SET image_path = 'shops/universal/061.jpg' WHERE template_key = 'universal.cable_pvs_2x25_black';
UPDATE product_templates SET image_path = 'shops/universal/065.jpg' WHERE template_key = 'universal.core_bit_75';
UPDATE product_templates SET image_path = 'shops/universal/069.jpg' WHERE template_key = 'universal.wrench_19';
UPDATE product_templates SET image_path = 'shops/universal/089.jpg' WHERE template_key = 'universal.roll_insulation_05';
UPDATE product_templates SET image_path = 'shops/plumbing/048.jpg' WHERE template_key = 'plumbing.washer_drain_hose_290';
UPDATE product_templates SET image_path = 'shops/plumbing/068.jpg' WHERE template_key = 'plumbing.sewer_pipe_50_3m';
UPDATE product_templates SET image_path = 'shops/plumbing/069.jpg' WHERE template_key = 'plumbing.sewer_pipe_75_3m';
UPDATE product_templates SET image_path = 'shops/plumbing/070.jpg' WHERE template_key = 'plumbing.sewer_pipe_150_3m';
UPDATE product_templates SET image_path = 'shops/plumbing/072.jpg' WHERE template_key = 'plumbing.sewer_clip_50';
UPDATE product_templates SET image_path = 'shops/plumbing/077.jpg' WHERE template_key = 'plumbing.sewer_tee_100_50';

UPDATE products p
SET image_path = t.image_path,
    updated_at = CURRENT_TIMESTAMP
FROM product_templates t
WHERE p.template_key = t.template_key
  AND p.image_path IS DISTINCT FROM t.image_path;

ALTER TABLE products
    DROP CONSTRAINT IF EXISTS products_variant_pair,
    DROP COLUMN IF EXISTS variant_label,
    DROP COLUMN IF EXISTS variant_group,
    DROP COLUMN IF EXISTS in_basket;

ALTER TABLE product_templates
    DROP CONSTRAINT IF EXISTS product_templates_variant_pair,
    DROP COLUMN IF EXISTS variant_label,
    DROP COLUMN IF EXISTS variant_group,
    DROP COLUMN IF EXISTS in_basket;

-- the three functions as migration 000001 wrote them: dropping the column would otherwise leave
-- bodies referring to products.in_basket, which fails at the next write rather than here
CREATE OR REPLACE FUNCTION refresh_basket_index(p_category text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('shop_basket_index'), hashtext(p_category));

    WITH basket AS (
        SELECT p.shop_id,
               SUM(p.price) AS basket_price
        FROM products p
        JOIN shops s ON s.id = p.shop_id
        WHERE p.template_key IS NOT NULL
          AND s.category = p_category
          AND NOT s.excluded_from_index
        GROUP BY p.shop_id
        HAVING COUNT(p.price) = COUNT(*)
    ),
    market AS (
        SELECT AVG(basket_price) AS market_basket FROM basket
    ),
    ranked AS (
        SELECT b.shop_id,
               b.basket_price::bigint                                AS basket_price,
               ROUND(b.basket_price / m.market_basket * 100)::bigint AS price_index
        FROM basket b
        CROSS JOIN market m
        WHERE m.market_basket > 0
    ),
    dropped AS (
        DELETE FROM shop_basket_index bi
        WHERE bi.shop_category = p_category
          AND NOT EXISTS (SELECT 1 FROM ranked r WHERE r.shop_id = bi.shop_id)
    )
    INSERT INTO shop_basket_index (shop_id, shop_category, basket_price, price_index, updated_at)
    SELECT r.shop_id, p_category, r.basket_price, r.price_index, CURRENT_TIMESTAMP
    FROM ranked r
    ON CONFLICT (shop_id) DO UPDATE
        SET shop_category = EXCLUDED.shop_category,
            basket_price  = EXCLUDED.basket_price,
            price_index   = EXCLUDED.price_index,
            updated_at    = EXCLUDED.updated_at
        WHERE shop_basket_index.basket_price  IS DISTINCT FROM EXCLUDED.basket_price
           OR shop_basket_index.price_index   IS DISTINCT FROM EXCLUDED.price_index
           OR shop_basket_index.shop_category IS DISTINCT FROM EXCLUDED.shop_category;
END;
$$;

CREATE OR REPLACE FUNCTION basket_index_after_products() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    cat text;
BEGIN
    FOR cat IN
        SELECT DISTINCT s.category
        FROM changed c
        JOIN shops s ON s.id = c.shop_id
        WHERE c.template_key IS NOT NULL
          AND (TG_OP = 'DELETE'
               OR c.price IS NOT NULL
               OR EXISTS (SELECT 1 FROM shop_basket_index bi WHERE bi.shop_id = c.shop_id))
        ORDER BY 1
    LOOP
        PERFORM refresh_basket_index(cat);
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION basket_index_after_product_update() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    cat text;
BEGIN
    FOR cat IN
        SELECT DISTINCT s.category
        FROM changed_new n
        JOIN changed_old o ON o.id = n.id
        JOIN shops s ON s.id = n.shop_id
        WHERE (n.template_key IS NOT NULL OR o.template_key IS NOT NULL)
          AND (n.price       IS DISTINCT FROM o.price
            OR n.template_key IS DISTINCT FROM o.template_key
            OR n.shop_id      IS DISTINCT FROM o.shop_id)
        ORDER BY 1
    LOOP
        PERFORM refresh_basket_index(cat);
    END LOOP;

    RETURN NULL;
END;
$$;

DO $$
DECLARE cat text;
BEGIN
    FOR cat IN SELECT DISTINCT category FROM shops ORDER BY 1 LOOP
        PERFORM refresh_basket_index(cat);
    END LOOP;
END;
$$;
