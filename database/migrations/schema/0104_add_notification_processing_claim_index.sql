-- Adds the in-flight notification claim index.

-- Bound lock waits and the index build so the migration fails instead of
-- stalling the app. The build blocks notification writes until this migration
-- commits.
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Index in-flight notification claims by claim time for the stale claim sweep
-- and the queue health report.
create index notification_processing_claimed_at_idx
    on notification (delivery_claimed_at)
    where delivery_status = 'processing';
