-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(43);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set otherCommunityID '00000000-0000-0000-0000-000000000002'
\set userAdminID '00000000-0000-0000-0000-000000000011'
\set userGroupsManagerID '00000000-0000-0000-0000-000000000012'
\set userPendingAdminID '00000000-0000-0000-0000-000000000014'
\set userRegularID '00000000-0000-0000-0000-000000000015'
\set userViewerID '00000000-0000-0000-0000-000000000013'

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

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    name,
    username
) values (
    :'userAdminID',
    gen_random_bytes(32),
    'admin@example.com',
    true,
    'Admin User',
    'adminuser'
), (
    :'userGroupsManagerID',
    gen_random_bytes(32),
    'groups-manager@example.com',
    true,
    'Groups Manager User',
    'groupsmanager'
), (
    :'userViewerID',
    gen_random_bytes(32),
    'viewer@example.com',
    true,
    'Viewer User',
    'vieweruser'
), (
    :'userPendingAdminID',
    gen_random_bytes(32),
    'pending-admin@example.com',
    true,
    'Pending Admin User',
    'pendingadmin'
), (
    :'userRegularID',
    gen_random_bytes(32),
    'regular@example.com',
    true,
    'Regular User',
    'regularuser'
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
