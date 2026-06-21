-- Add fixed RBAC roles for alliance and group management.

-- Alliance roles available for alliance team members.
create table alliance_role (
    alliance_role_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into alliance_role (alliance_role_id, display_name)
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

-- Add explicit alliance-team roles for permission checks.
alter table alliance_team
add column role text references alliance_role;

-- Set a default role for existing alliance team members, and make the role required.
update alliance_team
set role = 'admin'
where role is null;

alter table alliance_team
alter column role set not null;

create index alliance_team_role_idx on alliance_team (role);

-- Drop legacy auth functions.
drop function if exists user_owns_alliance(uuid, uuid);
drop function if exists user_owns_group(uuid, uuid, uuid);
drop function if exists user_owns_groups_in_alliance(uuid, uuid);
