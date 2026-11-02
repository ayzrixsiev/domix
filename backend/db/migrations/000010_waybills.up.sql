-- the list a customer sends from the Корзина tab, printed for staff as a накладная. the id is its number.
--
-- **named waybill because "basket" already means the price index** (shop_basket_index, products.in_basket).
--
-- **the photo lives in this row, never in imagestore**: that store is a public R2 bucket abroad holding
-- shop windows, and a handwritten list can carry a name or an address. here it stays in the country,
-- is private by construction and goes with the row when the account is deleted.
CREATE TABLE waybills (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- written by the app per submission, so a retry after a lost answer finds its row instead of a second number
    request_id VARCHAR(32) NOT NULL,
    shop_category VARCHAR(30) NOT NULL
        CHECK (shop_category IN ('universal', 'plumbing', 'wood', 'wallpaper')),
    items JSONB NOT NULL DEFAULT '[]',
    photo BYTEA,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (user_id, request_id),
    CONSTRAINT waybills_rows_or_photo CHECK ((photo IS NULL) = (jsonb_array_length(items) > 0))
);

CREATE INDEX idx_waybills_user ON waybills (user_id, id DESC);

-- the number is printed and read out over the phone, and no first customer should hold «№ 1»
ALTER SEQUENCE waybills_id_seq RESTART WITH 1001;
