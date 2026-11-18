-- Adds the unfinished payment job index.

-- Bound lock waits and the index build so the migration fails instead of
-- stalling the app. The build blocks payment_job writes until this migration
-- commits.
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Index unfinished payment jobs for the exhausted job and queue lookups.
create index payment_job_unfinished_idx
    on payment_job (payment_job_id)
    where status <> 'completed';
