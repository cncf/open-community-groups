-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(131);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000031'
\set communityID '00000000-0000-0000-0000-000000000001'
\set deletedGroupID '00000000-0000-0000-0000-000000000023'
\set groupID '00000000-0000-0000-0000-000000000021'
\set otherCategoryID '00000000-0000-0000-0000-000000000032'
\set otherCommunityGroupID '00000000-0000-0000-0000-000000000024'
\set otherCommunityID '00000000-0000-0000-0000-000000000002'
\set otherGroupID '00000000-0000-0000-0000-000000000022'
\set restrictedCategoryID '00000000-0000-0000-0000-000000000033'
\set restrictedCommunityID '00000000-0000-0000-0000-000000000003'
\set restrictedGroupID '00000000-0000-0000-0000-000000000025'
\set userCommunityAdminID '00000000-0000-0000-0000-000000000018'
\set userCommunityGroupsManagerID '00000000-0000-0000-0000-000000000014'
\set userCommunityPendingGroupsManagerID '00000000-0000-0000-0000-000000000019'
\set userCommunityViewerID '00000000-0000-0000-0000-000000000015'
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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'Seattle community for cloud native technologies',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
), (
    :'otherCommunityID',
    'platform-engineering-madrid',
    'Platform Engineering Madrid',
    'Madrid community for platform engineering discussions',
    'https://example.com/other-logo.png',
    'https://example.com/other-banner_mobile.png',
    'https://example.com/other-banner.png'
);

-- Restricted community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url,
    group_team_management_restricted
) values (
    :'restrictedCommunityID',
    'cloud-native-portland',
    'Cloud Native Portland',
    'Portland community for cloud native technologies',
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
    :'userCommunityAdminID',
    gen_random_bytes(32),
    'community-admin@example.com',
    true,
    'Community Admin',
    'communityadmin'
), (
    :'userCommunityGroupsManagerID',
    gen_random_bytes(32),
    'community-groups-manager@example.com',
    true,
    'Community Groups Manager',
    'communitygroupsmanager'
), (
    :'userCommunityPendingGroupsManagerID',
    gen_random_bytes(32),
    'community-pending-groups-manager@example.com',
    true,
    'Community Pending Groups Manager',
    'communitypendinggroupsmanager'
), (
    :'userCommunityViewerID',
    gen_random_bytes(32),
    'community-viewer@example.com',
    true,
    'Community Viewer',
    'communityviewer'
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
    community_id,
    name
) values (
    :'categoryID',
    :'communityID',
    'Technology'
), (
    :'otherCategoryID',
    :'otherCommunityID',
    'Platform Engineering'
), (
    :'restrictedCategoryID',
    :'restrictedCommunityID',
    'Technology'
);

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'communityID',
    :'categoryID',
    'Kubernetes Study Group',
    'kubernetes-study',
    'Weekly Kubernetes study and discussion group'
), (
    :'otherGroupID',
    :'communityID',
    :'categoryID',
    'Open Source Study Group',
    'open-source-study',
    'Weekly open source study and discussion group'
), (
    :'deletedGroupID',
    :'communityID',
    :'categoryID',
    'Deleted Study Group',
    'deleted-study',
    'Deleted group used for permission checks'
), (
    :'otherCommunityGroupID',
    :'otherCommunityID',
    :'otherCategoryID',
    'Internal Developer Platform',
    'internal-developer-platform',
    'Platform engineering group in a different community'
), (
    :'restrictedGroupID',
    :'restrictedCommunityID',
    :'restrictedCategoryID',
    'Restricted Kubernetes Study Group',
    'restricted-kubernetes-study',
    'Weekly Kubernetes study and discussion group in a restricted community'
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
    :'otherCommunityGroupID',
    'admin',
    :'userOtherGroupAdminID'
), (
    true,
    :'restrictedGroupID',
    'admin',
    :'userGroupAdminID'
);

-- Community team membership
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
