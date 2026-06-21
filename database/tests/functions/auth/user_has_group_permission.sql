-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(131);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000031'
\set allianceID '00000000-0000-0000-0000-000000000001'
\set deletedGroupID '00000000-0000-0000-0000-000000000023'
\set groupID '00000000-0000-0000-0000-000000000021'
\set otherCategoryID '00000000-0000-0000-0000-000000000032'
\set otherAllianceGroupID '00000000-0000-0000-0000-000000000024'
\set otherAllianceID '00000000-0000-0000-0000-000000000002'
\set otherGroupID '00000000-0000-0000-0000-000000000022'
\set restrictedCategoryID '00000000-0000-0000-0000-000000000033'
\set restrictedAllianceID '00000000-0000-0000-0000-000000000003'
\set restrictedGroupID '00000000-0000-0000-0000-000000000025'
\set userAllianceAdminID '00000000-0000-0000-0000-000000000018'
\set userAllianceGroupsManagerID '00000000-0000-0000-0000-000000000014'
\set userAlliancePendingGroupsManagerID '00000000-0000-0000-0000-000000000019'
\set userAllianceViewerID '00000000-0000-0000-0000-000000000015'
\set userDualRoleID '00000000-0000-0000-0000-000000000020'
\set userEventsManagerID '00000000-0000-0000-0000-000000000012'
\set userGroupAdminID '00000000-0000-0000-0000-000000000011'
\set userGroupViewerID '00000000-0000-0000-0000-000000000013'
\set userOtherGroupAdminID '00000000-0000-0000-0000-000000000021'
\set userPendingGroupAdminID '00000000-0000-0000-0000-000000000016'
\set userRegularID '00000000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'allianceID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'Seattle alliance for cloud native technologies',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
), (
    :'otherAllianceID',
    'platform-engineering-madrid',
    'Platform Engineering Madrid',
    'Madrid alliance for platform engineering discussions',
    'https://example.com/other-logo.png',
    'https://example.com/other-banner_mobile.png',
    'https://example.com/other-banner.png'
);

-- Restricted alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url,
    group_team_management_restricted
) values (
    :'restrictedAllianceID',
    'cloud-native-portland',
    'Cloud Native Portland',
    'Portland alliance for cloud native technologies',
    'https://example.com/restricted-logo.png',
    'https://example.com/restricted-banner_mobile.png',
    'https://example.com/restricted-banner.png',
    true
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    name,
    username
) values (
    :'userGroupAdminID',
    gen_random_bytes(32),
    'group-admin@example.com',
    true,
    'Group Admin',
    'groupadmin'
), (
    :'userEventsManagerID',
    gen_random_bytes(32),
    'events-manager@example.com',
    true,
    'Events Manager',
    'eventsmanager'
), (
    :'userGroupViewerID',
    gen_random_bytes(32),
    'group-viewer@example.com',
    true,
    'Group Viewer',
    'groupviewer'
), (
    :'userAllianceAdminID',
    gen_random_bytes(32),
    'alliance-admin@example.com',
    true,
    'Alliance Admin',
    'allianceadmin'
), (
    :'userAllianceGroupsManagerID',
    gen_random_bytes(32),
    'alliance-groups-manager@example.com',
    true,
    'Alliance Groups Manager',
    'alliancegroupsmanager'
), (
    :'userAlliancePendingGroupsManagerID',
    gen_random_bytes(32),
    'alliance-pending-groups-manager@example.com',
    true,
    'Alliance Pending Groups Manager',
    'alliancependinggroupsmanager'
), (
    :'userAllianceViewerID',
    gen_random_bytes(32),
    'alliance-viewer@example.com',
    true,
    'Alliance Viewer',
    'allianceviewer'
), (
    :'userDualRoleID',
    gen_random_bytes(32),
    'dual-role@example.com',
    true,
    'Dual Role',
    'dualrole'
), (
    :'userOtherGroupAdminID',
    gen_random_bytes(32),
    'other-group-admin@example.com',
    true,
    'Other Group Admin',
    'othergroupadmin'
), (
    :'userPendingGroupAdminID',
    gen_random_bytes(32),
    'pending-group-admin@example.com',
    true,
    'Pending Group Admin',
    'pendinggroupadmin'
), (
    :'userRegularID',
    gen_random_bytes(32),
    'regular@example.com',
    true,
    'Regular User',
    'regularuser'
);

-- Group category
insert into group_category (
    group_category_id,
    alliance_id,
    name
) values (
    :'categoryID',
    :'allianceID',
    'Technology'
), (
    :'otherCategoryID',
    :'otherAllianceID',
    'Platform Engineering'
), (
    :'restrictedCategoryID',
    :'restrictedAllianceID',
    'Technology'
);

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'allianceID',
    :'categoryID',
    'Kubernetes Study Group',
    'kubernetes-study',
    'Weekly Kubernetes study and discussion group'
), (
    :'otherGroupID',
    :'allianceID',
    :'categoryID',
    'Open Source Study Group',
    'open-source-study',
    'Weekly open source study and discussion group'
), (
    :'deletedGroupID',
    :'allianceID',
    :'categoryID',
    'Deleted Study Group',
    'deleted-study',
    'Deleted group used for permission checks'
), (
    :'otherAllianceGroupID',
    :'otherAllianceID',
    :'otherCategoryID',
    'Internal Developer Platform',
    'internal-developer-platform',
    'Platform engineering group in a different alliance'
), (
    :'restrictedGroupID',
    :'restrictedAllianceID',
    :'restrictedCategoryID',
    'Restricted Kubernetes Study Group',
    'restricted-kubernetes-study',
    'Weekly Kubernetes study and discussion group in a restricted alliance'
);

-- Soft-delete one group for permission checks
update "group" set
    active = false,
    deleted = true
where group_id = :'deletedGroupID';

-- Group team membership
insert into group_team (
    accepted,
    group_id,
    role,
    user_id
) values (
    true,
    :'groupID',
    'admin',
    :'userGroupAdminID'
), (
    true,
    :'groupID',
    'events-manager',
    :'userEventsManagerID'
), (
    true,
    :'groupID',
    'viewer',
    :'userGroupViewerID'
), (
    true,
    :'groupID',
    'viewer',
    :'userDualRoleID'
), (
    false,
    :'groupID',
    'admin',
    :'userPendingGroupAdminID'
), (
    true,
    :'deletedGroupID',
    'admin',
    :'userGroupAdminID'
), (
    true,
    :'otherGroupID',
    'admin',
    :'userOtherGroupAdminID'
), (
    true,
    :'otherAllianceGroupID',
    'admin',
    :'userOtherGroupAdminID'
), (
    true,
    :'restrictedGroupID',
    'admin',
    :'userGroupAdminID'
);

-- Alliance team membership
insert into alliance_team (
    accepted,
    alliance_id,
    role,
    user_id
) values (
    true,
    :'allianceID',
    'admin',
    :'userAllianceAdminID'
), (
    true,
    :'allianceID',
    'groups-manager',
    :'userAllianceGroupsManagerID'
), (
    true,
    :'allianceID',
    'viewer',
    :'userAllianceViewerID'
), (
    false,
    :'allianceID',
    'groups-manager',
    :'userAlliancePendingGroupsManagerID'
), (
    true,
    :'allianceID',
    'groups-manager',
    :'userDualRoleID'
), (
    true,
    :'restrictedAllianceID',
    'admin',
    :'userAllianceAdminID'
), (
    true,
    :'restrictedAllianceID',
    'groups-manager',
    :'userAllianceGroupsManagerID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep tested group permissions aligned with canonical catalog
with tested_permissions (
    permission
) as (
    values
        ('group.events.write'),
        ('group.members.write'),
        ('group.read'),
        ('group.settings.write'),
        ('group.sponsors.write'),
        ('group.team.write')
)
select is(
    (
        select count(*)
        from (
            (
                select group_permission_id
                from group_permission
                except
                select permission
                from tested_permissions
            )
            union all
            (
                select permission
                from tested_permissions
                except
                select group_permission_id
                from group_permission
            )
        ) mismatches
    ),
    0::bigint,
    'Tested group permissions should match the canonical catalog'
);

-- Should enforce the full group role-permission matrix
with actors (
    actor,
    alliance_id,
    group_id,
    user_id,
    allowed_permissions
) as (
    values
        (
            'alliance-admin',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userAllianceAdminID'::uuid,
            array[
                'group.events.write',
                'group.members.write',
                'group.read',
                'group.settings.write',
                'group.sponsors.write',
                'group.team.write'
            ]::text[]
        ),
        (
            'alliance-admin-other-group',
            :'allianceID'::uuid,
            :'otherGroupID'::uuid,
            :'userAllianceAdminID'::uuid,
            array[
                'group.events.write',
                'group.members.write',
                'group.read',
                'group.settings.write',
                'group.sponsors.write',
                'group.team.write'
            ]::text[]
        ),
        (
            'alliance-groups-manager',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userAllianceGroupsManagerID'::uuid,
            array[
                'group.events.write',
                'group.members.write',
                'group.read',
                'group.settings.write',
                'group.sponsors.write',
                'group.team.write'
            ]::text[]
        ),
        (
            'alliance-pending-groups-manager',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userAlliancePendingGroupsManagerID'::uuid,
            array[]::text[]
        ),
        (
            'alliance-viewer',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userAllianceViewerID'::uuid,
            array[
                'group.read'
            ]::text[]
        ),
        (
            'deleted-group-alliance-admin',
            :'allianceID'::uuid,
            :'deletedGroupID'::uuid,
            :'userAllianceAdminID'::uuid,
            array[]::text[]
        ),
        (
            'deleted-group-group-admin',
            :'allianceID'::uuid,
            :'deletedGroupID'::uuid,
            :'userGroupAdminID'::uuid,
            array[]::text[]
        ),
        (
            'dual-role-viewer-and-groups-manager',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userDualRoleID'::uuid,
            array[
                'group.events.write',
                'group.members.write',
                'group.read',
                'group.settings.write',
                'group.sponsors.write',
                'group.team.write'
            ]::text[]
        ),
        (
            'group-admin',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userGroupAdminID'::uuid,
            array[
                'group.events.write',
                'group.members.write',
                'group.read',
                'group.settings.write',
                'group.sponsors.write',
                'group.team.write'
            ]::text[]
        ),
        (
            'group-events-manager',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userEventsManagerID'::uuid,
            array[
                'group.events.write',
                'group.read'
            ]::text[]
        ),
        (
            'group-pending-admin',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userPendingGroupAdminID'::uuid,
            array[]::text[]
        ),
        (
            'group-viewer',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userGroupViewerID'::uuid,
            array[
                'group.read'
            ]::text[]
        ),
        (
            'other-alliance-group-admin',
            :'otherAllianceID'::uuid,
            :'otherAllianceGroupID'::uuid,
            :'userOtherGroupAdminID'::uuid,
            array[
                'group.events.write',
                'group.members.write',
                'group.read',
                'group.settings.write',
                'group.sponsors.write',
                'group.team.write'
            ]::text[]
        ),
        (
            'other-group-admin-out-of-scope',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userOtherGroupAdminID'::uuid,
            array[]::text[]
        ),
        (
            'regular-user',
            :'allianceID'::uuid,
            :'groupID'::uuid,
            :'userRegularID'::uuid,
            array[]::text[]
        ),
        (
            'wrong-alliance-alliance-admin',
            :'otherAllianceID'::uuid,
            :'groupID'::uuid,
            :'userAllianceAdminID'::uuid,
            array[]::text[]
        ),
        (
            'wrong-alliance-group-admin',
            :'otherAllianceID'::uuid,
            :'groupID'::uuid,
            :'userGroupAdminID'::uuid,
            array[]::text[]
        ),
        (
            'wrong-group-group-admin',
            :'allianceID'::uuid,
            :'otherGroupID'::uuid,
            :'userGroupAdminID'::uuid,
            array[]::text[]
        )
), permissions (
    permission
) as (
    values
        ('group.events.write'),
        ('group.members.write'),
        ('group.read'),
        ('group.settings.write'),
        ('group.sponsors.write'),
        ('group.team.write'),
        ('group.unknown')
), test_cases as (
    select
        a.actor,
        a.alliance_id,
        a.group_id,
        a.user_id,
        p.permission,
        p.permission = any (a.allowed_permissions) as expected
    from actors a
    cross join permissions p
)
select is(
    user_has_group_permission(alliance_id, group_id, user_id, permission),
    expected,
    format(
        'Actor=%s user_id=%s alliance_id=%s group_id=%s permission=%s should be %s',
        actor,
        user_id,
        alliance_id,
        group_id,
        permission,
        case when expected then 'allowed' else 'blocked' end
    )
)
from test_cases
order by actor, permission;

-- Should block group admins from managing teams in restricted alliances
select is(
    user_has_group_permission(
        :'restrictedAllianceID'::uuid,
        :'restrictedGroupID'::uuid,
        :'userGroupAdminID'::uuid,
        'group.team.write'
    ),
    false,
    'Group admin should not manage group team when alliance restriction is enabled'
);

-- Should allow alliance admins to manage teams in restricted alliances
select is(
    user_has_group_permission(
        :'restrictedAllianceID'::uuid,
        :'restrictedGroupID'::uuid,
        :'userAllianceAdminID'::uuid,
        'group.team.write'
    ),
    true,
    'Alliance admin should manage group team when alliance restriction is enabled'
);

-- Should allow alliance groups managers to manage teams in restricted alliances
select is(
    user_has_group_permission(
        :'restrictedAllianceID'::uuid,
        :'restrictedGroupID'::uuid,
        :'userAllianceGroupsManagerID'::uuid,
        'group.team.write'
    ),
    true,
    'Alliance groups manager should manage group team when alliance restriction is enabled'
);

-- Should keep group admin non-team permissions unchanged in restricted alliances
select is(
    user_has_group_permission(
        :'restrictedAllianceID'::uuid,
        :'restrictedGroupID'::uuid,
        :'userGroupAdminID'::uuid,
        'group.events.write'
    ),
    true,
    'Group admin event permissions should remain unchanged when alliance restriction is enabled'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
