-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(43);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0a0d0000-0000-0000-0000-000000000001'
\set otherCommunityID '0a0d0000-0000-0000-0000-000000000002'
\set userAdminID '0a0d0000-0000-0000-0000-000000000003'
\set userGroupsManagerID '0a0d0000-0000-0000-0000-000000000004'
\set userPendingAdminID '0a0d0000-0000-0000-0000-000000000005'
\set userRegularID '0a0d0000-0000-0000-0000-000000000006'
\set userViewerID '0a0d0000-0000-0000-0000-000000000007'

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
    logo_url
) values (
    :'communityID',
    'community-permission-community',
    'Community Permission Community',
    'Test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'otherCommunityID',
    'community-permission-other-community',
    'Community Permission Other Community',
    'Other test community',
    'https://example.com/other-banner-mobile.png',
    'https://example.com/other-banner.png',
    'https://example.com/other-logo.png'
);

-- Users
insert into "user" (
    user_id,
    name,
    auth_hash,
    email,
    email_verified,
    username
) values (
    :'userAdminID',
    'Admin User',
    gen_random_bytes(32),
    'admin@example.com',
    true,
    'adminuser'
), (
    :'userGroupsManagerID',
    'Groups Manager User',
    gen_random_bytes(32),
    'groups-manager@example.com',
    true,
    'groupsmanager'
), (
    :'userViewerID',
    'Viewer User',
    gen_random_bytes(32),
    'viewer@example.com',
    true,
    'vieweruser'
), (
    :'userPendingAdminID',
    'Pending Admin User',
    gen_random_bytes(32),
    'pending-admin@example.com',
    true,
    'pendingadmin'
), (
    :'userRegularID',
    'Regular User',
    gen_random_bytes(32),
    'regular@example.com',
    true,
    'regularuser'
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
    :'userAdminID'
), (
    true,
    :'communityID',
    'groups-manager',
    :'userGroupsManagerID'
), (
    true,
    :'communityID',
    'viewer',
    :'userViewerID'
), (
    false,
    :'communityID',
    'admin',
    :'userPendingAdminID'
), (
    true,
    :'otherCommunityID',
    'admin',
    :'userRegularID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep tested community permissions aligned with canonical catalog
with tested_permissions (
    permission
) as (
    values
        ('community.groups.write'),
        ('community.read'),
        ('community.settings.write'),
        ('community.taxonomy.write'),
        ('community.team.write')
)
select is(
    (
        select count(*)
        from (
            (
                select community_permission_id
                from community_permission
                except
                select permission
                from tested_permissions
            )
            union all
            (
                select permission
                from tested_permissions
                except
                select community_permission_id
                from community_permission
            )
        ) mismatches
    ),
    0::bigint,
    'Tested community permissions should match the canonical catalog'
);

-- Should enforce the full community role-permission matrix
with actors (
    actor,
    community_id,
    user_id,
    allowed_permissions
) as (
    values
        (
            'admin',
            :'communityID'::uuid,
            :'userAdminID'::uuid,
            array[
                'community.groups.write',
                'community.read',
                'community.settings.write',
                'community.taxonomy.write',
                'community.team.write'
            ]::text[]
        ),
        (
            'admin-wrong-community',
            :'otherCommunityID'::uuid,
            :'userAdminID'::uuid,
            array[]::text[]
        ),
        (
            'groups-manager',
            :'communityID'::uuid,
            :'userGroupsManagerID'::uuid,
            array[
                'community.groups.write',
                'community.read'
            ]::text[]
        ),
        (
            'pending-admin',
            :'communityID'::uuid,
            :'userPendingAdminID'::uuid,
            array[]::text[]
        ),
        (
            'regular-user',
            :'communityID'::uuid,
            :'userRegularID'::uuid,
            array[]::text[]
        ),
        (
            'regular-user-other-community-admin',
            :'otherCommunityID'::uuid,
            :'userRegularID'::uuid,
            array[
                'community.groups.write',
                'community.read',
                'community.settings.write',
                'community.taxonomy.write',
                'community.team.write'
            ]::text[]
        ),
        (
            'viewer',
            :'communityID'::uuid,
            :'userViewerID'::uuid,
            array[
                'community.read'
            ]::text[]
        )
), permissions (
    permission
) as (
    values
        ('community.groups.write'),
        ('community.read'),
        ('community.settings.write'),
        ('community.taxonomy.write'),
        ('community.team.write'),
        ('community.unknown')
), test_cases as (
    select
        a.actor,
        a.community_id,
        a.user_id,
        p.permission,
        p.permission = any (a.allowed_permissions) as expected
    from actors a
    cross join permissions p
)
select is(
    user_has_community_permission(community_id, user_id, permission),
    expected,
    format(
        'Actor=%s user_id=%s community_id=%s permission=%s should be %s',
        actor,
        user_id,
        community_id,
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
