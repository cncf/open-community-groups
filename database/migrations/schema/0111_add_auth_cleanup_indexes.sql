-- Adds expiry indexes for auth session and email verification cleanup.

---- tern: disable-tx ----

-- Bound lock waits and concurrent index builds so rollout fails fast instead of stalling.
set lock_timeout = '5s';
set statement_timeout = '10min';

-- Index auth session expiry so cleanup sweeps avoid full table scans.
drop index concurrently if exists auth_session_expires_at_idx;
create index concurrently auth_session_expires_at_idx
    on auth_session (expires_at);

-- Index email verification code creation time so cleanup sweeps avoid full table scans.
drop index concurrently if exists email_verification_code_created_at_idx;
create index concurrently email_verification_code_created_at_idx
    on email_verification_code (created_at);

reset lock_timeout;
reset statement_timeout;
