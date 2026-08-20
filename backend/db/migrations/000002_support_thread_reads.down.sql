-- Dropping this loses only "which conversations have been looked at". `unanswered` is derived in
-- SQL and is untouched by this migration in either direction, so the inbox falls back to exactly the
-- behaviour it had before: every thread with a newer user message than support reply counts as
-- waiting, whether or not anybody has read it.
DROP TABLE IF EXISTS support_thread_reads;
