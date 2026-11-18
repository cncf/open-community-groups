-- Adds the community audit log action index.

-- Bound lock waits and the index build so the migration fails instead of
-- stalling the app. The build blocks audit_log writes until this migration
-- commits, and dropping the index it replaces in 0102 keeps the exclusive
-- audit_log lock out of this window.
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Index community audit rows by action, so the community audit log reads only
-- the listed actions instead of every group and event row of the community.
create index audit_log_community_id_action_idx on audit_log (community_id, action);
