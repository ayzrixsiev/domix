-- The columns come back empty and the tables come back without their rows: this is a schema rollback,
-- not a restore. The phone normalization is deliberately not undone - there is nothing to undo it to.

ALTER TABLE shops ADD COLUMN IF NOT EXISTS rating NUMERIC(2, 1) NOT NULL DEFAULT 0.0;
ALTER TABLE shops ADD COLUMN IF NOT EXISTS image_url VARCHAR(255);

CREATE TABLE IF NOT EXISTS support_messages (
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    from_support BOOLEAN NOT NULL DEFAULT FALSE,
    body         TEXT NOT NULL,
    created_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_support_messages_thread ON support_messages (user_id, id);

CREATE TABLE IF NOT EXISTS support_thread_reads (
    admin_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    thread_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_id   BIGINT      NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (admin_id, thread_user_id)
);
