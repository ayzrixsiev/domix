-- Which support conversations an admin has already looked at.
--
-- **This is the one piece of stored state the support inbox deliberately did without**, so it is
-- worth being precise about what it is and what it is not.
--
-- `unanswered` - messages from a user newer than the last thing support said - stays exactly as it
-- was: derived in SQL, nothing to forget to clear, and still the queue the founder triages on. A
-- thread that was opened and read but not answered still shows as waiting, which is the whole reason
-- that number exists.
--
-- This table answers the *other* question: has anybody here seen the new message yet. Opening a
-- thread clears it; opening a thread does not answer anybody. So the sidebar badge can stop shouting
-- about a conversation the founder has already read while the inbox keeps listing it as unanswered.
--
-- It stores a **watermark, not a flag**: `last_read_id` is the id of the newest message that had been
-- written when the thread was opened. Message ids only ever go up, so "unread" stays derived -
-- `COUNT(*) WHERE id > last_read_id` - and a message arriving one second later is unread by
-- arithmetic rather than by something remembering to set a bit. A boolean would need clearing on
-- every insert, which is the staleness the original design was avoiding.
--
-- Keyed per admin because "seen" is a fact about a person, not about the conversation. There is
-- exactly one admin today (§6: the role can only be set with SQL), so this costs nothing now and is
-- the difference between a correct model and one that quietly clears a colleague's queue later.
CREATE TABLE IF NOT EXISTS support_thread_reads (
    -- who did the reading
    admin_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- whose thread was read. a thread *is* one user's messages, so it is addressed by user id here
    -- exactly as it is in the api - there is no thread row to point at.
    thread_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    last_read_id   BIGINT      NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (admin_id, thread_user_id)
);

-- the inbox reads every row belonging to one admin on each load, and the primary key's leading
-- column already serves that, so there is no second index here on purpose.
