-- name: ListSupportThread :many
SELECT id, user_id, from_support, body, created_at
FROM support_messages
WHERE user_id = $1
ORDER BY id;

-- name: CreateSupportMessage :one
INSERT INTO support_messages (user_id, from_support, body)
VALUES ($1, $2, $3)
RETURNING id, user_id, from_support, body, created_at;

-- name: CountRecentSupportMessages :one
SELECT COUNT(*)::bigint
FROM support_messages
WHERE user_id = $1
  AND NOT from_support
  AND created_at > CURRENT_TIMESTAMP - INTERVAL '1 minute';

-- name: AdminSupportThreads :many
--
-- the inbox, and it now carries **two** counts that answer two different questions. keeping them
-- apart is the whole design (migration 000002):
--
--   unanswered - messages from the user newer than the last thing support said. still derived,
--                still the triage queue: reading a thread does not settle it, only answering does.
--   unread     - messages from the user newer than the last time *this admin* opened the thread.
--                this is the one that clears when the founder reads a conversation, and it is what
--                the sidebar badge counts.
--
-- $1 is the admin doing the asking, which is why the read watermark is joined per-caller rather than
-- read as a property of the thread.
WITH last_message AS (
    SELECT DISTINCT ON (user_id)
           user_id, id, body, from_support, created_at
    FROM support_messages
    ORDER BY user_id, id DESC
),
last_reply AS (
    SELECT user_id, MAX(id) AS id
    FROM support_messages
    WHERE from_support
    GROUP BY user_id
),
totals AS (
    SELECT m.user_id,
           COUNT(*)::bigint AS total,
           COUNT(*) FILTER (WHERE NOT m.from_support AND m.id > COALESCE(r.id, 0))::bigint AS unanswered,
           COUNT(*) FILTER (WHERE NOT m.from_support AND m.id > COALESCE(rd.last_read_id, 0))::bigint AS unread
    FROM support_messages m
    LEFT JOIN last_reply r ON r.user_id = m.user_id
    -- COALESCE below, not a WHERE: a thread this admin has never opened has no row here at all, and
    -- every message in it is unread. an INNER JOIN would have made a brand-new conversation the one
    -- thing the badge never mentions.
    LEFT JOIN support_thread_reads rd
           ON rd.admin_id = $1 AND rd.thread_user_id = m.user_id
    GROUP BY m.user_id, r.id, rd.last_read_id
)
SELECT
    u.id    AS user_id,
    u.name,
    u.phone,
    u.role,
    t.total,
    t.unanswered,
    t.unread,
    l.body         AS last_body,
    l.from_support AS last_from_support,
    l.created_at   AS last_at
FROM totals t
JOIN users u ON u.id = t.user_id
JOIN last_message l ON l.user_id = t.user_id
ORDER BY l.id DESC
LIMIT $2 OFFSET $3;

-- name: AdminMarkSupportThreadRead :exec
--
-- moves this admin's watermark to the newest message in the thread. run by the handler that returns
-- a conversation, because that request *is* the reading - see the note on Admin.SupportThread.
--
-- the id is taken from the database rather than from the caller: a client that named its own
-- watermark could mark a thread read past messages it had never been sent.
--
-- GREATEST on conflict, so the watermark can only ever move forwards. two tabs open on the same
-- inbox, or a reply racing a poll, would otherwise let an older read drag it back and resurrect a
-- notification for a message somebody had already answered.
INSERT INTO support_thread_reads (admin_id, thread_user_id, last_read_id)
VALUES (
    $1,
    $2,
    COALESCE((SELECT MAX(id) FROM support_messages WHERE user_id = $2), 0)
)
ON CONFLICT (admin_id, thread_user_id) DO UPDATE
SET last_read_id = GREATEST(support_thread_reads.last_read_id, EXCLUDED.last_read_id),
    updated_at   = CURRENT_TIMESTAMP;

-- name: AdminUnreadSupportThreads :one
--
-- how many conversations hold something this admin has not seen - the sidebar badge, carried on the
-- dashboard request so it is right before the section has ever been opened.
--
-- conversations, not messages: three questions from one person is one person waiting, and a badge
-- that counts messages makes a chatty user look like a queue.
SELECT COUNT(*)::bigint AS threads
FROM (
    SELECT m.user_id
    FROM support_messages m
    LEFT JOIN support_thread_reads r
           ON r.admin_id = $1 AND r.thread_user_id = m.user_id
    WHERE NOT m.from_support
      AND m.id > COALESCE(r.last_read_id, 0)
    GROUP BY m.user_id
) unread;
