-- Add RBAC permission identifiers and role-to-permission grant mappings.

-- Canonical community permission identifiers.
create table community_permission (
    community_permission_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into community_permission (community_permission_id, display_name)
values
    ('community.groups.write', 'Groups Write'),
    ('community.read', 'Read'),
    ('community.settings.write', 'Settings Write'),
    ('community.taxonomy.write', 'Taxonomy Write'),
    ('community.team.write', 'Team Write');

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

-- Map community roles to community-scoped permissions.
create table community_role_community_permission (
    community_permission_id text not null references community_permission,
    community_role_id text not null references community_role,

    primary key (community_permission_id, community_role_id)
);

insert into community_role_community_permission (community_role_id, community_permission_id)
values
    ('admin', 'community.groups.write'),
    ('admin', 'community.read'),
    ('admin', 'community.settings.write'),
    ('admin', 'community.taxonomy.write'),
    ('admin', 'community.team.write'),
    ('groups-manager', 'community.groups.write'),
    ('groups-manager', 'community.read'),
    ('viewer', 'community.read');

-- Map community roles to group-scoped permissions.
create table community_role_group_permission (
    community_role_id text not null references community_role,
    group_permission_id text not null references group_permission,

    primary key (community_role_id, group_permission_id)
);

insert into community_role_group_permission (community_role_id, group_permission_id)
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
