-- Drop unique constraint on user.legacy_id.
alter table "user" drop constraint user_legacy_id_key;

-- Drop unique constraint on group.legacy_id.
alter table "group" drop constraint group_legacy_id_key;

-- Drop unique constraint on event.legacy_id.
alter table event drop constraint event_legacy_id_key;
