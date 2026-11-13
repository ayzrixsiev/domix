-- name: SpendGeoCall :one
-- the last 24 hours rather than a calendar day: yandex does not say where its day starts, and no
-- calendar day in any zone can then hold more than the cap. no row back means the budget is spent.
WITH spent AS (
    SELECT coalesce(sum(used), 0)::int AS total
    FROM geo_calls
    WHERE product = @product AND hour > now() - interval '24 hours'
)
INSERT INTO geo_calls (product, hour, used)
SELECT @product, date_trunc('hour', now()), 1
FROM spent
WHERE spent.total < @daily_cap::int
ON CONFLICT (product, hour) DO UPDATE SET used = geo_calls.used + 1
RETURNING used;

-- name: ForgetOldGeoCalls :exec
DELETE FROM geo_calls WHERE hour < now() - interval '48 hours';

-- name: GeoUsage :many
-- the window SpendGeoCall refuses on, so the panel shows the number the cap is read against
SELECT product::text AS product,
       coalesce(sum(used) FILTER (WHERE hour = date_trunc('hour', now())), 0)::int AS this_hour,
       coalesce(sum(used), 0)::int AS last_day
FROM geo_calls
WHERE hour > now() - interval '24 hours'
GROUP BY product;
