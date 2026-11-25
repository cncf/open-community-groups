-- Updates the meeting sync claim indexes to include retry backoff scheduling.

---- tern: disable-tx ----

-- Bound lock waits and concurrent index builds so rollout fails fast instead of stalling.
set lock_timeout = '5s';
set statement_timeout = '10min';

-- Include meeting_next_sync_at so due claim scans skip backed-off events.
drop index concurrently if exists event_meeting_sync_claim_idx;
create index concurrently event_meeting_sync_claim_idx
    on event (meeting_sync_claimed_at, meeting_next_sync_at)
    where meeting_in_sync = false or meeting_sync_claimed_at is not null;

-- Include next_sync_at so due orphan delete scans skip backed-off meetings.
drop index concurrently if exists meeting_sync_claim_idx;
create index concurrently meeting_sync_claim_idx
    on meeting (sync_claimed_at, next_sync_at)
    where event_id is null and session_id is null;

-- Include meeting_next_sync_at so due claim scans skip backed-off sessions.
drop index concurrently if exists session_meeting_sync_claim_idx;
create index concurrently session_meeting_sync_claim_idx
    on session (meeting_sync_claimed_at, meeting_next_sync_at)
    where meeting_in_sync = false or meeting_sync_claimed_at is not null;

reset lock_timeout;
reset statement_timeout;
