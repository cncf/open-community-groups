-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(105);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000031'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000021'
\set otherCommunityID '00000000-0000-0000-0000-000000000002'
\set otherGroupID '00000000-0000-0000-0000-000000000022'
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
);

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
    :'otherGroupID',
    'admin',
    :'userOtherGroupAdminID'
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
);

-- ============================================================================
-- TESTS
-- ============================================================================

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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
