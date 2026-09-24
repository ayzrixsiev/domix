-- What a customer saved from a product grid, one row per (person, product).
--
-- **It points at one shop's product row, not at a catalogue item.** The heart is on a tile that
-- already carries a price and a shop, and that is what the customer saved - "цемент у Азиза за
-- 52 000", not "цемент somewhere". So `ON DELETE CASCADE` on product_id is right: a shop that stops
-- selling the item takes the saved card with it, where keeping it would leave a card opening onto
-- nothing.
--
-- The primary key is the whole index. It is one row per pair, which makes a double tap idempotent,
-- and its leading column serves the only query there is - everything this user saved.
CREATE TABLE favorites (
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, product_id)
);
