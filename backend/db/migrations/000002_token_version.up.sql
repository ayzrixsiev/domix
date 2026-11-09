-- a token carries the value it was minted with, and RequireAuth refuses one that is behind the row:
-- bumping this ends every session of one account without rotating JWT_SECRET for everybody
ALTER TABLE users ADD COLUMN token_version INT NOT NULL DEFAULT 0;
