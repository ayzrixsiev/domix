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
           COUNT(*) FILTER (WHERE NOT m.from_support AND m.id > COALESCE(r.id, 0))::bigint AS unanswered
    FROM support_messages m
    LEFT JOIN last_reply r ON r.user_id = m.user_id
    GROUP BY m.user_id, r.id
)
SELECT
    u.id    AS user_id,
    u.name,
    u.phone,
    u.role,
    t.total,
    t.unanswered,
    l.body         AS last_body,
    l.from_support AS last_from_support,
    l.created_at   AS last_at
FROM totals t
JOIN users u ON u.id = t.user_id
JOIN last_message l ON l.user_id = t.user_id
ORDER BY l.id DESC
LIMIT $1 OFFSET $2;
