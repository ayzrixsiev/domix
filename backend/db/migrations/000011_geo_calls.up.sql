-- calls made to Yandex's free geocoder and geosuggest, counted per hour, so the daily budget survives a
-- restart. **a key that keeps going over 1000 a day is blocked for good**, and every deploy restarts the
-- process: a counter held in ram would start from zero each time.
CREATE TABLE geo_calls (
    product VARCHAR(16) NOT NULL CHECK (product IN ('geocoder', 'suggest')),
    hour TIMESTAMP WITH TIME ZONE NOT NULL,
    used INTEGER NOT NULL,
    PRIMARY KEY (product, hour)
);
