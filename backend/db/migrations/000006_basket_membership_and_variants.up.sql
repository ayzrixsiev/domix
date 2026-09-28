-- Two facts a template row did not carry before: whether it counts towards the price comparison,
-- and whether it is one size of a product that has several.
--
-- **why membership had to become a column.** the comparison is all-or-nothing (refresh_basket_index
-- below), so adding one product to a template dropped *every* shop of that market out of it until
-- every owner had typed a price for the new row. that made the catalogue effectively unextendable
-- once there were real shops. now a new product arrives outside the basket, gets priced at leisure,
-- and is voted in when enough shops have a number for it.

ALTER TABLE product_templates
    -- new rows default to FALSE: adding a product must never be the thing that breaks a live market
    ADD COLUMN in_basket BOOLEAN NOT NULL DEFAULT FALSE,

    -- **display only.** one row is still one sellable thing with one price - the index, the search
    -- and the anomaly report all aggregate per row, and collapsing sizes into one row with several
    -- prices would break all three. these two columns only tell the app to draw one tile with a
    -- chip per size instead of five near-identical tiles.
    ADD COLUMN variant_group VARCHAR(80),
    ADD COLUMN variant_label VARCHAR(40),
    ADD CONSTRAINT product_templates_variant_pair
        CHECK ((variant_group IS NULL) = (variant_label IS NULL));

-- every row that exists today *is* the basket - that is what the comparison has been built on
UPDATE product_templates SET in_basket = TRUE;

-- mirrored onto products rather than joined for. the same argument as name/category/unit: the basket
-- triggers run inside writes that never touch product_templates, and a join there would make every
-- price edit depend on a second table. AdminSyncTemplateUpdate keeps the copy honest.
-- **the default differs from the template table's, and the direction is the point.** a template row
-- defaults to FALSE because adding a product must not break a live market. a products row defaults to
-- TRUE because the failure modes are not symmetric: an INSERT that forgets to copy the flag would
-- otherwise produce a shop whose basket is empty, which is a shop silently missing from the price
-- comparison with nothing on any screen to say why. only template rows are read (the basket query
-- filters template_key IS NOT NULL), so a custom product's value is never consulted.
ALTER TABLE products
    ADD COLUMN in_basket BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN variant_group VARCHAR(80),
    ADD COLUMN variant_label VARCHAR(40),
    ADD CONSTRAINT products_variant_pair
        CHECK ((variant_group IS NULL) = (variant_label IS NULL));

-- an owner's own product is never part of the shared basket. not load-bearing - the basket query
-- ignores these rows anyway - but a column that says the wrong thing gets read by somebody eventually
UPDATE products SET in_basket = FALSE WHERE template_key IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- The sizes, and the photo they share.
--
-- Fifteen groups found by reading the catalogue: rows whose names differ only in a number. Written
-- out key by key rather than derived by pattern, because a regex over product names is a thing that
-- silently groups two unrelated products the day somebody adds one.
--
-- **each group keeps the photo of its first member and the rest point at that same file**, which is
-- what leaves 18 catalogue files unreferenced - they are swept from the admin panel, not here: a
-- migration that deleted image files could not be rolled back.
-- ─────────────────────────────────────────────────────────────────────────────────────────────────

-- universal
UPDATE product_templates SET variant_group = 'Скотч упаковочный', variant_label = '4,5х50' WHERE template_key = 'universal.tape_45x50';
UPDATE product_templates SET variant_group = 'Скотч упаковочный', variant_label = '4,5х40', image_path = 'shops/universal/001.jpg' WHERE template_key = 'universal.tape_45x40';

UPDATE product_templates SET variant_group = 'Шпатель', variant_label = '250 мм' WHERE template_key = 'universal.spatula_250';
UPDATE product_templates SET variant_group = 'Шпатель', variant_label = '400 мм', image_path = 'shops/universal/012.jpg' WHERE template_key = 'universal.spatula_400';

UPDATE product_templates SET variant_group = 'Диск шлифовальный EN-PD-100', variant_label = '50' WHERE template_key = 'universal.grinding_disc_50';
UPDATE product_templates SET variant_group = 'Диск шлифовальный EN-PD-100', variant_label = '1000', image_path = 'shops/universal/020.jpg' WHERE template_key = 'universal.grinding_disc_1000';
UPDATE product_templates SET variant_group = 'Диск шлифовальный EN-PD-100', variant_label = '1500', image_path = 'shops/universal/020.jpg' WHERE template_key = 'universal.grinding_disc_1500';

UPDATE product_templates SET variant_group = 'Бур по бетону SDS plus Lit', variant_label = '6х120' WHERE template_key = 'universal.sds_drill_6x120';
UPDATE product_templates SET variant_group = 'Бур по бетону SDS plus Lit', variant_label = '10х350', image_path = 'shops/universal/025.jpg' WHERE template_key = 'universal.sds_drill_10x350';

UPDATE product_templates SET variant_group = 'Рулетка Lit', variant_label = '5 м' WHERE template_key = 'universal.tape_measure_5m';
UPDATE product_templates SET variant_group = 'Рулетка Lit', variant_label = '10 м', image_path = 'shops/universal/028.jpg' WHERE template_key = 'universal.tape_measure_10m';

UPDATE product_templates SET variant_group = 'Лампочка светодиодная', variant_label = '10 Вт' WHERE template_key = 'universal.led_lamp_10w';
UPDATE product_templates SET variant_group = 'Лампочка светодиодная', variant_label = '60 Вт', image_path = 'shops/universal/037.jpg' WHERE template_key = 'universal.led_lamp_60w';

UPDATE product_templates SET variant_group = 'Кисть для водоэмульсионных красок', variant_label = '3"' WHERE template_key = 'universal.brush_3';
UPDATE product_templates SET variant_group = 'Кисть для водоэмульсионных красок', variant_label = '4"', image_path = 'shops/universal/046.jpg' WHERE template_key = 'universal.brush_4';

UPDATE product_templates SET variant_group = 'Кабель медный ПВС, чёрный', variant_label = '2х1,5' WHERE template_key = 'universal.cable_pvs_2x15_black';
UPDATE product_templates SET variant_group = 'Кабель медный ПВС, чёрный', variant_label = '2х2,5', image_path = 'shops/universal/060.jpg' WHERE template_key = 'universal.cable_pvs_2x25_black';

UPDATE product_templates SET variant_group = 'Коронка алмазная', variant_label = '25 мм' WHERE template_key = 'universal.core_bit_25';
UPDATE product_templates SET variant_group = 'Коронка алмазная', variant_label = '75 мм', image_path = 'shops/universal/064.jpg' WHERE template_key = 'universal.core_bit_75';

UPDATE product_templates SET variant_group = 'Ключ комбинированный', variant_label = '10 мм' WHERE template_key = 'universal.wrench_10';
UPDATE product_templates SET variant_group = 'Ключ комбинированный', variant_label = '19 мм', image_path = 'shops/universal/068.jpg' WHERE template_key = 'universal.wrench_19';

UPDATE product_templates SET variant_group = 'Изоляция рулонная (синтепон), завод', variant_label = '03' WHERE template_key = 'universal.roll_insulation_03';
UPDATE product_templates SET variant_group = 'Изоляция рулонная (синтепон), завод', variant_label = '05', image_path = 'shops/universal/088.jpg' WHERE template_key = 'universal.roll_insulation_05';

-- plumbing
UPDATE product_templates SET variant_group = 'Сливной шланг для стиральной машины', variant_label = '190 мм' WHERE template_key = 'plumbing.washer_drain_hose_190';
UPDATE product_templates SET variant_group = 'Сливной шланг для стиральной машины', variant_label = '290 мм', image_path = 'shops/plumbing/047.jpg' WHERE template_key = 'plumbing.washer_drain_hose_290';

UPDATE product_templates SET variant_group = 'VERO Канализационная труба 3 м', variant_label = 'Ø100' WHERE template_key = 'plumbing.sewer_pipe_100_3m';
UPDATE product_templates SET variant_group = 'VERO Канализационная труба 3 м', variant_label = 'Ø50',  image_path = 'shops/plumbing/067.jpg' WHERE template_key = 'plumbing.sewer_pipe_50_3m';
UPDATE product_templates SET variant_group = 'VERO Канализационная труба 3 м', variant_label = 'Ø75',  image_path = 'shops/plumbing/067.jpg' WHERE template_key = 'plumbing.sewer_pipe_75_3m';
UPDATE product_templates SET variant_group = 'VERO Канализационная труба 3 м', variant_label = 'Ø150', image_path = 'shops/plumbing/067.jpg' WHERE template_key = 'plumbing.sewer_pipe_150_3m';

UPDATE product_templates SET variant_group = 'VERO (к) Клипса', variant_label = 'Ø100' WHERE template_key = 'plumbing.sewer_clip_100';
UPDATE product_templates SET variant_group = 'VERO (к) Клипса', variant_label = 'Ø50', image_path = 'shops/plumbing/071.jpg' WHERE template_key = 'plumbing.sewer_clip_50';

UPDATE product_templates SET variant_group = 'VERO (к) Тройник 90°', variant_label = '100/100' WHERE template_key = 'plumbing.sewer_tee_100_100';
UPDATE product_templates SET variant_group = 'VERO (к) Тройник 90°', variant_label = '100/50', image_path = 'shops/plumbing/076.jpg' WHERE template_key = 'plumbing.sewer_tee_100_50';

-- and into every shop already seeded from those templates. this is what the sync button does for
-- later edits; a migration cannot leave the two disagreeing.
UPDATE products p
SET variant_group = t.variant_group,
    variant_label = t.variant_label,
    image_path    = t.image_path,
    updated_at    = CURRENT_TIMESTAMP
FROM product_templates t
WHERE p.template_key = t.template_key
  AND t.variant_group IS NOT NULL
  AND (p.variant_group IS DISTINCT FROM t.variant_group
    OR p.variant_label IS DISTINCT FROM t.variant_label
    OR p.image_path    IS DISTINCT FROM t.image_path);

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- The index now totals the basket rows, not every template row.
-- ─────────────────────────────────────────────────────────────────────────────────────────────────

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
          -- **the one line this migration exists for**: a template row outside the basket is not
          -- part of the comparison, so leaving it unpriced no longer disqualifies a shop
          AND p.in_basket
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

-- rows appeared or disappeared. **`c.in_basket` is a saving that matters now**: pushing a new
-- product into 500 shops inserts 500 rows that cannot move any total, and without this line each
-- such sync would recompute the whole market anyway.
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
          AND c.in_basket
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

-- an existing row changed. **in_basket joins the three columns this watches, and it has to**: voting
-- a product into the basket is an UPDATE that touches no price, so without this line the index would
-- keep answering about the old basket until some unrelated write moved it.
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
          AND (n.price        IS DISTINCT FROM o.price
            OR n.template_key IS DISTINCT FROM o.template_key
            OR n.shop_id      IS DISTINCT FROM o.shop_id
            OR n.in_basket    IS DISTINCT FROM o.in_basket)
        ORDER BY 1
    LOOP
        PERFORM refresh_basket_index(cat);
    END LOOP;

    RETURN NULL;
END;
$$;

-- the baskets changed shape, so every market's totals are stale until this runs
DO $$
DECLARE cat text;
BEGIN
    FOR cat IN SELECT DISTINCT category FROM shops ORDER BY 1 LOOP
        PERFORM refresh_basket_index(cat);
    END LOOP;
END;
$$;
