-- Updates the event meeting sync claim and start indexes.

-- Bound lock waits and index builds so the migration fails instead of stalling
-- the app. The drops block event reads and writes until this migration
-- commits, and each drop runs before its rebuild so the exclusive lock is
-- taken once, up front.
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Index out of sync and claimed event meetings, so stale claim recovery, whose
-- claimed rows may hold any meeting_in_sync value, can use the claim index too.
drop index event_meeting_sync_claim_idx;
create index event_meeting_sync_claim_idx on event (meeting_sync_claimed_at)
    where meeting_in_sync = false or meeting_sync_claimed_at is not null;

-- Cover the explore search columns in the listed event start index, so the
-- search matcher reads the date range with an index-only scan.
drop index event_starts_at_idx;
create index event_starts_at_idx on event (starts_at)
    include (event_category_id, event_id, event_kind_id, group_id, location, test_event)
    where published = true and canceled = false and deleted = false;
