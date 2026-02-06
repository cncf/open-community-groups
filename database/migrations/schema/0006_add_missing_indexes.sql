-- Add some indexes for user-facing list and dashboard queries.

create index community_team_pending_user_created_at_idx
    on community_team (user_id, created_at desc)
    where accepted = false;

create index event_group_not_deleted_starts_at_idx
    on event (group_id, starts_at, event_id)
    where deleted = false;

create index group_active_created_at_idx
    on "group" (created_at desc)
    where active = true;

create index group_community_active_created_at_idx
    on "group" (community_id, created_at desc)
    where active = true;

create index group_team_pending_user_created_at_idx
    on group_team (user_id, created_at desc)
    where accepted = false;
