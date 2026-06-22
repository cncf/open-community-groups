-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(131);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '0a0e0000-0000-0000-0000-000000000001'
\set deletedGroupID '0a0e0000-0000-0000-0000-000000000002'
\set groupCategoryID '0a0e0000-0000-0000-0000-000000000003'
\set groupID '0a0e0000-0000-0000-0000-000000000004'
\set otherAllianceGroupID '0a0e0000-0000-0000-0000-000000000005'
\set otherAllianceID '0a0e0000-0000-0000-0000-000000000006'
\set otherGroupCategoryID '0a0e0000-0000-0000-0000-000000000007'
\set otherGroupID '0a0e0000-0000-0000-0000-000000000008'
\set restrictedAllianceID '0a0e0000-0000-0000-0000-000000000009'
\set restrictedGroupCategoryID '0a0e0000-0000-0000-0000-000000000010'
\set restrictedGroupID '0a0e0000-0000-0000-0000-000000000011'
\set userAllianceAdminID '0a0e0000-0000-0000-0000-000000000012'
\set userAllianceGroupsManagerID '0a0e0000-0000-0000-0000-000000000013'
\set userAlliancePendingGroupsManagerID '0a0e0000-0000-0000-0000-000000000014'
\set userAllianceViewerID '0a0e0000-0000-0000-0000-000000000015'
\set userDualRoleID '0a0e0000-0000-0000-0000-000000000016'
\set userEventsManagerID '0a0e0000-0000-0000-0000-000000000017'
\set userGroupAdminID '0a0e0000-0000-0000-0000-000000000018'
\set userGroupViewerID '0a0e0000-0000-0000-0000-000000000019'
\set userOtherGroupAdminID '0a0e0000-0000-0000-0000-000000000020'
\set userPendingGroupAdminID '0a0e0000-0000-0000-0000-000000000021'
\set userRegularID '0a0e0000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    group_team_management_restricted,
    logo_url
) values (
    :'allianceID',
    'group-permission-alliance',
    'Group Permission Alliance',
    'Test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    false,
    'https://example.com/logo.png'
), (
    :'otherAllianceID',
    'group-permission-other-alliance',
    'Group Permission Other Alliance',
    'Other test alliance',
    'https://example.com/other-banner-mobile.png',
    'https://example.com/other-banner.png',
    false,
    'https://example.com/other-logo.png'
), (
    :'restrictedAllianceID',
    'group-permission-restricted-alliance',
    'Group Permission Restricted Alliance',
    'Restricted test alliance',
    'https://example.com/restricted-banner-mobile.png',
    'https://example.com/restricted-banner.png',
    true,
    'https://example.com/restricted-logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values
    (:'groupCategoryID', :'allianceID', 'Technology'),
    (:'otherGroupCategoryID', :'otherAllianceID', 'Platform Engineering'),
    (:'restrictedGroupCategoryID', :'restrictedAllianceID', 'Technology');

-- Users
insert into "user" (
    user_id,
    name,
    auth_hash,
    email,
    email_verified,
    username
) values (
    :'userGroupAdminID',
    'Group Admin',
    gen_random_bytes(32),
    'group-admin@example.com',
    true,
    'groupadmin'
), (
    :'userEventsManagerID',
    'Events Manager',
    gen_random_bytes(32),
    'events-manager@example.com',
    true,
    'eventsmanager'
), (
    :'userGroupViewerID',
    'Group Viewer',
    gen_random_bytes(32),
    'group-viewer@example.com',
    true,
    'groupviewer'
), (
    :'userAllianceAdminID',
    'Alliance Admin',
    gen_random_bytes(32),
    'alliance-admin@example.com',
    true,
    'allianceadmin'
), (
    :'userAllianceGroupsManagerID',
    'Alliance Groups Manager',
    gen_random_bytes(32),
    'alliance-groups-manager@example.com',
    true,
    'alliancegroupsmanager'
), (
    :'userAlliancePendingGroupsManagerID',
    'Alliance Pending Groups Manager',
    gen_random_bytes(32),
    'alliance-pending-groups-manager@example.com',
    true,
    'alliancependinggroupsmanager'
), (
    :'userAllianceViewerID',
    'Alliance Viewer',
    gen_random_bytes(32),
    'alliance-viewer@example.com',
    true,
    'allianceviewer'
), (
    :'userDualRoleID',
    'Dual Role',
    gen_random_bytes(32),
    'dual-role@example.com',
    true,
    'dualrole'
), (
    :'userOtherGroupAdminID',
    'Other Group Admin',
    gen_random_bytes(32),
    'other-group-admin@example.com',
    true,
    'othergroupadmin'
), (
    :'userPendingGroupAdminID',
    'Pending Group Admin',
    gen_random_bytes(32),
    'pending-group-admin@example.com',
    true,
    'pendinggroupadmin'
), (
    :'userRegularID',
    'Regular User',
    gen_random_bytes(32),
    'regular@example.com',
    true,
    'regularuser'
);

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    description,
    slug
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Kubernetes Study Group',
    'Weekly Kubernetes study and discussion group',
    'kubernetes-study'
), (
    :'otherGroupID',
    :'allianceID',
    :'groupCategoryID',
    'Open Source Study Group',
    'Weekly open source study and discussion group',
    'open-source-study'
), (
    :'deletedGroupID',
    :'allianceID',
    :'groupCategoryID',
    'Deleted Study Group',
    'Deleted group used for permission checks',
    'deleted-study'
), (
    :'otherAllianceGroupID',
    :'otherAllianceID',
    :'otherGroupCategoryID',
    'Internal Developer Platform',
    'Platform engineering group in a different alliance',
    'internal-developer-platform'
), (
    :'restrictedGroupID',
    :'restrictedAllianceID',
    :'restrictedGroupCategoryID',
    'Restricted Kubernetes Study Group',
    'Weekly Kubernetes study and discussion group in a restricted alliance',
    'restricted-kubernetes-study'
);

-- Soft-delete one group for permission checks
update "group" set
    active = false,
    deleted = true
where group_id = :'deletedGroupID';

-- Group team memberships
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

-- Alliance team memberships
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
