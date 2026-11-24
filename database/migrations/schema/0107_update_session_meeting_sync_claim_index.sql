-- Updates the session meeting sync claim index.

-- Bound lock waits and the index build so the migration fails instead of
-- stalling the app. The drop blocks session reads and writes until this
-- migration commits, and it runs before the rebuild so the exclusive lock is
-- taken once, up front.
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Index out of sync and claimed session meetings like the event claim index.
drop index session_meeting_sync_claim_idx;
create index session_meeting_sync_claim_idx on session (meeting_sync_claimed_at)
    where meeting_in_sync = false or meeting_sync_claimed_at is not null;
