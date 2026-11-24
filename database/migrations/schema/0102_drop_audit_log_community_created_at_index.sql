-- Drops the community audit log created_at index.

-- Bound the lock wait so the migration fails instead of stalling the app. The
-- drop blocks audit_log reads and writes until this migration commits.
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Drop the community created_at audit index, which the community audit log no
-- longer reads.
drop index audit_log_community_id_created_at_idx;
