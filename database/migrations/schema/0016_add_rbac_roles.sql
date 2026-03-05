-- Add fixed RBAC roles for community and group management.

-- Community roles available for community team members.
create table community_role (
    community_role_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into community_role (community_role_id, display_name)
values
    ('admin', 'Admin'),
    ('groups-manager', 'Groups Manager'),
    ('viewer', 'Viewer');

-- Group roles available for group team members.
insert into group_role (group_role_id, display_name)
values
    ('admin', 'Admin'),
    ('events-manager', 'Events Manager'),
    ('viewer', 'Viewer');

-- Normalize legacy organizer assignments before removing the role.
update group_team
set role = 'admin'
where role = 'organizer';

-- Delete the legacy organizer role, which is no longer needed.
delete from group_role
where group_role_id = 'organizer';

-- Add explicit community-team roles for permission checks.
alter table community_team
add column role text references community_role;

-- Set a default role for existing community team members, and make the role required.
update community_team
set role = 'admin'
where role is null;

alter table community_team
alter column role set not null;

create index community_team_role_idx on community_team (role);

-- Drop legacy auth functions.
drop function if exists user_owns_community(uuid, uuid);
drop function if exists user_owns_group(uuid, uuid, uuid);
drop function if exists user_owns_groups_in_community(uuid, uuid);
