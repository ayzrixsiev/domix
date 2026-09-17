-- Product search: an index it can use, over one spelling of every name.
--
-- A leading wildcard ("%кабель%") cannot use an ordinary index, so every search read every priced
-- product. A trigram index (pg_trgm) stores every three-letter run of a name, which is what a
-- substring needs to be looked up rather than scanned for - and why a query needs one word of three
-- letters (minSearchWordLen).
--
-- It indexes the name as SearchProducts compares it: lowercased, ё written as е (19 catalogue names
-- are spelled with ё and nobody types it). **The query's expression must match this one character for
-- character**, or postgres stops using the index. Partial on `price IS NOT NULL`: unpriced rows are
-- never searched.

-- lower() folds case by the database's locale, and under the C locale it leaves Cyrillic alone -
-- "цемент" would stop finding "Цемент" with nothing to report it. Refused here rather than in prod.
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
