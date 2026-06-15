-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(131);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0a0e0000-0000-0000-0000-000000000001'
\set deletedGroupID '0a0e0000-0000-0000-0000-000000000002'
\set groupCategoryID '0a0e0000-0000-0000-0000-000000000003'
\set groupID '0a0e0000-0000-0000-0000-000000000004'
\set otherCommunityGroupID '0a0e0000-0000-0000-0000-000000000005'
\set otherCommunityID '0a0e0000-0000-0000-0000-000000000006'
\set otherGroupCategoryID '0a0e0000-0000-0000-0000-000000000007'
\set otherGroupID '0a0e0000-0000-0000-0000-000000000008'
\set restrictedCommunityID '0a0e0000-0000-0000-0000-000000000009'
\set restrictedGroupCategoryID '0a0e0000-0000-0000-0000-000000000010'
\set restrictedGroupID '0a0e0000-0000-0000-0000-000000000011'
\set userCommunityAdminID '0a0e0000-0000-0000-0000-000000000012'
\set userCommunityGroupsManagerID '0a0e0000-0000-0000-0000-000000000013'
\set userCommunityPendingGroupsManagerID '0a0e0000-0000-0000-0000-000000000014'
\set userCommunityViewerID '0a0e0000-0000-0000-0000-000000000015'
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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    group_team_management_restricted,
    logo_url
) values (
    :'communityID',
    'group-permission-community',
    'Group Permission Community',
    'Test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    false,
    'https://example.com/logo.png'
), (
    :'otherCommunityID',
    'group-permission-other-community',
    'Group Permission Other Community',
    'Other test community',
    'https://example.com/other-banner-mobile.png',
    'https://example.com/other-banner.png',
    false,
    'https://example.com/other-logo.png'
), (
    :'restrictedCommunityID',
    'group-permission-restricted-community',
    'Group Permission Restricted Community',
    'Restricted test community',
    'https://example.com/restricted-banner-mobile.png',
    'https://example.com/restricted-banner.png',
    true,
    'https://example.com/restricted-logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategoryID', :'communityID', 'Technology'),
    (:'otherGroupCategoryID', :'otherCommunityID', 'Platform Engineering'),
    (:'restrictedGroupCategoryID', :'restrictedCommunityID', 'Technology');

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
    :'userCommunityAdminID',
    'Community Admin',
    gen_random_bytes(32),
    'community-admin@example.com',
    true,
    'communityadmin'
), (
    :'userCommunityGroupsManagerID',
    'Community Groups Manager',
    gen_random_bytes(32),
    'community-groups-manager@example.com',
    true,
    'communitygroupsmanager'
), (
    :'userCommunityPendingGroupsManagerID',
    'Community Pending Groups Manager',
    gen_random_bytes(32),
    'community-pending-groups-manager@example.com',
    true,
    'communitypendinggroupsmanager'
), (
    :'userCommunityViewerID',
    'Community Viewer',
    gen_random_bytes(32),
    'community-viewer@example.com',
    true,
    'communityviewer'
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
    community_id,
    group_category_id,
    name,
    description,
    slug
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Kubernetes Study Group',
    'Weekly Kubernetes study and discussion group',
    'kubernetes-study'
), (
    :'otherGroupID',
    :'communityID',
    :'groupCategoryID',
    'Open Source Study Group',
    'Weekly open source study and discussion group',
    'open-source-study'
), (
    :'deletedGroupID',
    :'communityID',
    :'groupCategoryID',
    'Deleted Study Group',
    'Deleted group used for permission checks',
    'deleted-study'
), (
    :'otherCommunityGroupID',
    :'otherCommunityID',
    :'otherGroupCategoryID',
    'Internal Developer Platform',
    'Platform engineering group in a different community',
    'internal-developer-platform'
), (
    :'restrictedGroupID',
    :'restrictedCommunityID',
    :'restrictedGroupCategoryID',
    'Restricted Kubernetes Study Group',
    'Weekly Kubernetes study and discussion group in a restricted community',
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
    :'otherCommunityGroupID',
    'admin',
    :'userOtherGroupAdminID'
), (
    true,
    :'restrictedGroupID',
    'admin',
    :'userGroupAdminID'
);

-- Community team memberships
insert into community_team (
    accepted,
    community_id,
    role,
    user_id
) values (
    true,
    :'communityID',
    'admin',
    :'userCommunityAdminID'
), (
    true,
    :'communityID',
    'groups-manager',
    :'userCommunityGroupsManagerID'
), (
    true,
    :'communityID',
    'viewer',
    :'userCommunityViewerID'
), (
    false,
    :'communityID',
    'groups-manager',
    :'userCommunityPendingGroupsManagerID'
), (
    true,
    :'communityID',
    'groups-manager',
    :'userDualRoleID'
), (
    true,
    :'restrictedCommunityID',
    'admin',
    :'userCommunityAdminID'
), (
    true,
    :'restrictedCommunityID',
    'groups-manager',
    :'userCommunityGroupsManagerID'
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
    community_id,
    group_id,
    user_id,
    allowed_permissions
) as (
    values
        (
            'community-admin',
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userCommunityAdminID'::uuid,
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
            'community-admin-other-group',
            :'communityID'::uuid,
            :'otherGroupID'::uuid,
            :'userCommunityAdminID'::uuid,
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
            'community-groups-manager',
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userCommunityGroupsManagerID'::uuid,
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
            'community-pending-groups-manager',
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userCommunityPendingGroupsManagerID'::uuid,
            array[]::text[]
        ),
        (
            'community-viewer',
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userCommunityViewerID'::uuid,
            array[
                'group.read'
            ]::text[]
        ),
        (
            'deleted-group-community-admin',
            :'communityID'::uuid,
            :'deletedGroupID'::uuid,
            :'userCommunityAdminID'::uuid,
            array[]::text[]
        ),
        (
            'deleted-group-group-admin',
            :'communityID'::uuid,
            :'deletedGroupID'::uuid,
            :'userGroupAdminID'::uuid,
            array[]::text[]
        ),
        (
            'dual-role-viewer-and-groups-manager',
            :'communityID'::uuid,
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
            :'communityID'::uuid,
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
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userEventsManagerID'::uuid,
            array[
                'group.events.write',
                'group.read'
            ]::text[]
        ),
        (
            'group-pending-admin',
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userPendingGroupAdminID'::uuid,
            array[]::text[]
        ),
        (
            'group-viewer',
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userGroupViewerID'::uuid,
            array[
                'group.read'
            ]::text[]
        ),
        (
            'other-community-group-admin',
            :'otherCommunityID'::uuid,
            :'otherCommunityGroupID'::uuid,
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
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userOtherGroupAdminID'::uuid,
            array[]::text[]
        ),
        (
            'regular-user',
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userRegularID'::uuid,
            array[]::text[]
        ),
        (
            'wrong-community-community-admin',
            :'otherCommunityID'::uuid,
            :'groupID'::uuid,
            :'userCommunityAdminID'::uuid,
            array[]::text[]
        ),
        (
            'wrong-community-group-admin',
            :'otherCommunityID'::uuid,
            :'groupID'::uuid,
            :'userGroupAdminID'::uuid,
            array[]::text[]
        ),
        (
            'wrong-group-group-admin',
            :'communityID'::uuid,
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
        a.community_id,
        a.group_id,
        a.user_id,
        p.permission,
        p.permission = any (a.allowed_permissions) as expected
    from actors a
    cross join permissions p
)
select is(
    user_has_group_permission(community_id, group_id, user_id, permission),
    expected,
    format(
        'Actor=%s user_id=%s community_id=%s group_id=%s permission=%s should be %s',
        actor,
        user_id,
        community_id,
        group_id,
        permission,
        case when expected then 'allowed' else 'blocked' end
    )
)
from test_cases
order by actor, permission;

-- Should block group admins from managing teams in restricted communities
select is(
    user_has_group_permission(
        :'restrictedCommunityID'::uuid,
        :'restrictedGroupID'::uuid,
        :'userGroupAdminID'::uuid,
        'group.team.write'
    ),
    false,
    'Group admin should not manage group team when community restriction is enabled'
);

-- Should allow community admins to manage teams in restricted communities
select is(
    user_has_group_permission(
        :'restrictedCommunityID'::uuid,
        :'restrictedGroupID'::uuid,
        :'userCommunityAdminID'::uuid,
        'group.team.write'
    ),
    true,
    'Community admin should manage group team when community restriction is enabled'
);

-- Should allow community groups managers to manage teams in restricted communities
select is(
    user_has_group_permission(
        :'restrictedCommunityID'::uuid,
        :'restrictedGroupID'::uuid,
        :'userCommunityGroupsManagerID'::uuid,
        'group.team.write'
    ),
    true,
    'Community groups manager should manage group team when community restriction is enabled'
);

-- Should keep group admin non-team permissions unchanged in restricted communities
select is(
    user_has_group_permission(
        :'restrictedCommunityID'::uuid,
        :'restrictedGroupID'::uuid,
        :'userGroupAdminID'::uuid,
        'group.events.write'
    ),
    true,
    'Group admin event permissions should remain unchanged when community restriction is enabled'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
