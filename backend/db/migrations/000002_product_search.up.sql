-- Product search: an index it can use, over one spelling of every name.
--
-- a leading wildcard cannot use an ordinary index, so every search read every priced product. a
-- trigram index stores every three-letter run, which is why a query needs one word of three letters.
--
-- **the query's expression must match this one character for character**, or postgres silently stops
-- using the index and every search becomes a sequential scan.

-- under the C locale lower() leaves Cyrillic alone, so "цемент" would stop finding "Цемент" with
-- nothing to report it. refused here rather than in production.
DO $$
BEGIN
    IF lower('ЦЁ') <> 'цё' THEN
        RAISE EXCEPTION 'this database does not lowercase Cyrillic, so product search would be case-sensitive - recreate it with a UTF-8 locale such as en_US.UTF-8';
    END IF;
END $$;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX idx_products_search_name ON products
    USING gin (translate(lower(name), 'ё', 'е') gin_trgm_ops)
    WHERE price IS NOT NULL;
