-- What a category's basket cost, one row per market per day.
--
-- **The only fact in this product that cannot be recomputed.** `shop_basket_index` is a view over
-- `products.price`, so it always answers about *now*: the moment an owner retypes a price, what the
-- basket cost yesterday is gone, and no column anywhere remembers it. Everything else on the admin
-- dashboard is derived from current rows and would survive this table being dropped; "средний чек по
-- категории за месяц" is the one question that needs something to have been written down at the time.
--
-- **Keyed by (day, category) so writing it is idempotent.** The job behind it (startBasketHistory in
-- cmd/api/main.go) upserts every hour rather than once at midnight: a server restarted daily at the
-- wrong moment would otherwise skip whole days, and re-running the same day's aggregate costs one
-- cheap query and keeps today's point current to within the hour. `day` is a DATE and not a
-- timestamp for the same reason - the row *is* the day, and a time component would let two rows
-- exist for one.
--
-- **A day with no row is a day the server was not running**, and the chart draws the gap rather than
-- interpolating it. That is honest and it is also why nothing here is NOT NULL DEFAULT 0: a zero
-- would be a claim that the market was free.
CREATE TABLE IF NOT EXISTS basket_history (
    day        DATE   NOT NULL,
    category   TEXT   NOT NULL,

    -- how many shops were in the comparison that day. it is what makes an average readable later:
    -- a jump from 3 shops to 9 explains a move that would otherwise look like a price change.
    shops      INT    NOT NULL,

    avg_basket BIGINT NOT NULL,
    min_basket BIGINT NOT NULL,
    max_basket BIGINT NOT NULL,

    PRIMARY KEY (day, category)
);

-- the dashboard reads the last 30 days across every category at once, and the primary key's leading
-- column already serves a range scan on `day`, so there is no second index here on purpose.
