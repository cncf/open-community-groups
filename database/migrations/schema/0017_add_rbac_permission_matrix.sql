-- Add RBAC permission identifiers and role-to-permission grant mappings.

-- Canonical alliance permission identifiers.
create table alliance_permission (
    alliance_permission_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into alliance_permission (alliance_permission_id, display_name)
values
    ('alliance.groups.write', 'Groups Write'),
    ('alliance.read', 'Read'),
    ('alliance.settings.write', 'Settings Write'),
    ('alliance.taxonomy.write', 'Taxonomy Write'),
    ('alliance.team.write', 'Team Write');

-- Canonical group permission identifiers.
create table group_permission (
    group_permission_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into group_permission (group_permission_id, display_name)
values
    ('group.events.write', 'Events Write'),
    ('group.members.write', 'Members Write'),
    ('group.read', 'Read'),
    ('group.settings.write', 'Settings Write'),
    ('group.sponsors.write', 'Sponsors Write'),
    ('group.team.write', 'Team Write');

-- Map alliance roles to alliance-scoped permissions.
create table alliance_role_alliance_permission (
    alliance_permission_id text not null references alliance_permission,
    alliance_role_id text not null references alliance_role,

    primary key (alliance_permission_id, alliance_role_id)
);

insert into alliance_role_alliance_permission (alliance_role_id, alliance_permission_id)
values
    ('admin', 'alliance.groups.write'),
    ('admin', 'alliance.read'),
    ('admin', 'alliance.settings.write'),
    ('admin', 'alliance.taxonomy.write'),
    ('admin', 'alliance.team.write'),
    ('groups-manager', 'alliance.groups.write'),
    ('groups-manager', 'alliance.read'),
    ('viewer', 'alliance.read');

-- Map alliance roles to group-scoped permissions.
create table alliance_role_group_permission (
    alliance_role_id text not null references alliance_role,
    group_permission_id text not null references group_permission,

    primary key (alliance_role_id, group_permission_id)
);

insert into alliance_role_group_permission (alliance_role_id, group_permission_id)
values
    ('admin', 'group.events.write'),
    ('admin', 'group.members.write'),
    ('admin', 'group.read'),
    ('admin', 'group.settings.write'),
    ('admin', 'group.sponsors.write'),
    ('admin', 'group.team.write'),
    ('groups-manager', 'group.events.write'),
    ('groups-manager', 'group.members.write'),
    ('groups-manager', 'group.read'),
    ('groups-manager', 'group.settings.write'),
    ('groups-manager', 'group.sponsors.write'),
    ('groups-manager', 'group.team.write'),
    ('viewer', 'group.read');

-- Map group roles to group-scoped permissions.
create table group_role_group_permission (
    group_permission_id text not null references group_permission,
    group_role_id text not null references group_role,

    primary key (group_permission_id, group_role_id)
);

insert into group_role_group_permission (group_role_id, group_permission_id)
values
    ('admin', 'group.events.write'),
    ('admin', 'group.members.write'),
    ('admin', 'group.read'),
    ('admin', 'group.settings.write'),
    ('admin', 'group.sponsors.write'),
    ('admin', 'group.team.write'),
    ('events-manager', 'group.events.write'),
    ('events-manager', 'group.read'),
    ('viewer', 'group.read');
