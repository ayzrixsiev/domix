-- Three removals, all of the same kind: things the schema carried that nothing filled in.

-- 1. Support. The inbox is being rebuilt from nothing, so its tables go rather than sit empty
-- waiting for a design they may not match. `support_thread_reads` first: it references users, and
-- its whole meaning is a watermark into the table below.
DROP TABLE IF EXISTS support_thread_reads;
DROP TABLE IF EXISTS support_messages;

-- 2. Two columns on `shops` that no statement ever wrote. `rating` was always 0.0 and was being
-- ORDER BY'd as a tie-breaker that could never break a tie; `image_url` had no upload endpoint
-- behind it, so every shop in the app drew an empty photo slot. Both travelled to the phone on
-- every map load. Reviews and shop photos come back as their own features, with their own columns.
ALTER TABLE shops DROP COLUMN IF EXISTS rating;
ALTER TABLE shops DROP COLUMN IF EXISTS image_url;

-- 3. `users.phone` holds whatever the retired telegram handshake reported, and telegram sent some
-- clients' numbers with a leading '+'. Nothing writes that form any more, so the rows are moved onto
-- the one canonical spelling the code flow uses (998XXXXXXXXX) and the double lookup in
-- endpoints.findUser goes with them.
--
-- The NOT EXISTS guard is what makes this safe to run on real data: if both spellings of one number
-- somehow exist as two accounts, the UNIQUE index would refuse the update and take the whole
-- migration down. Here the odd row is left alone instead, to be looked at by hand.
WITH normalized AS (
    SELECT id,
           CASE
               WHEN length(digits) = 9  THEN '998' || digits
               WHEN length(digits) = 12 AND digits LIKE '998%' THEN digits
               ELSE phone
           END AS canonical
    FROM (
        SELECT id, phone,
               regexp_replace(regexp_replace(phone, '\D', '', 'g'), '^00', '') AS digits
        FROM users
    ) stripped
)
UPDATE users u
SET phone = n.canonical
FROM normalized n
WHERE u.id = n.id
  AND u.phone <> n.canonical
  AND NOT EXISTS (SELECT 1 FROM users other WHERE other.phone = n.canonical);
