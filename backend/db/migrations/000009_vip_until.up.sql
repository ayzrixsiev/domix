-- VIP placement gets an expiry date and a way to be set that isn't a hand-written UPDATE.
--
-- Migration 000007 added `shops.is_vip` as a boolean, with the note that it should become a
-- timestamp once there was a way to buy a placement. There still isn't billing, but the boolean has
-- a failure mode that doesn't need billing to bite: turning a placement *off* is a thing a person
-- has to remember to do. A shop that stops paying keeps its carousel slot until somebody notices,
-- and "somebody notices" is not a mechanism. Nothing in the system knows the placement was ever
-- meant to end, so there is nothing to notice it with.
--
-- A date fixes that by inverting who has to act: the grant carries its own end, and expiry is the
-- default rather than an intervention. Selling a month of VIP becomes one call that says when the
-- month is up.
ALTER TABLE shops
ADD COLUMN IF NOT EXISTS vip_until TIMESTAMP WITH TIME ZONE;

-- carry over whatever the boolean currently says. thirty days is a guess, because a boolean does
-- not record when the placement started or what was paid for - which is the whole point of the
-- change. it only affects rows that were flipped by hand locally.
UPDATE shops SET vip_until = CURRENT_TIMESTAMP + INTERVAL '30 days' WHERE is_vip;

ALTER TABLE shops
DROP COLUMN IF EXISTS is_vip;

-- "who is VIP right now" is `vip_until > now()`, run on every home screen load. partial, because a
-- shop that has never held a placement is the overwhelming majority and has nothing to say here.
CREATE INDEX IF NOT EXISTS idx_shops_vip_until
    ON shops (vip_until)
    WHERE vip_until IS NOT NULL;
