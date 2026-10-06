-- Add community-scoped custom notifications sent to group teams.

-- Allow custom notifications to be scoped to a community.
alter table custom_notification
    add column community_id uuid references community (community_id) on delete cascade;

-- Require exactly one custom notification scope.
alter table custom_notification drop constraint custom_notification_check;
alter table custom_notification add constraint custom_notification_scope_check check (
    num_nonnulls(community_id, event_id, group_id) = 1
);

-- Support community custom notification lookups and cascades.
create index custom_notification_community_id_idx on custom_notification (community_id);

-- Register the community custom notification kind, which is always sent.
insert into notification_kind (name) values ('community-custom');

-- Drop signatures replaced by the community-aware custom notification functions.
drop function if exists enqueue_tracked_custom_notification(
    text, jsonb, jsonb, uuid[], uuid, uuid, uuid, int, text, text
);
drop function if exists track_custom_notification(uuid, uuid, uuid, int, text, text);
