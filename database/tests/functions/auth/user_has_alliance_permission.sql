-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(43);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '0a0d0000-0000-0000-0000-000000000001'
\set otherAllianceID '0a0d0000-0000-0000-0000-000000000002'
\set userAdminID '0a0d0000-0000-0000-0000-000000000003'
\set userGroupsManagerID '0a0d0000-0000-0000-0000-000000000004'
\set userPendingAdminID '0a0d0000-0000-0000-0000-000000000005'
\set userRegularID '0a0d0000-0000-0000-0000-000000000006'
\set userViewerID '0a0d0000-0000-0000-0000-000000000007'

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
    logo_url
) values (
    :'allianceID',
    'alliance-permission-alliance',
    'Alliance Permission Alliance',
    'Test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'otherAllianceID',
    'alliance-permission-other-alliance',
    'Alliance Permission Other Alliance',
    'Other test alliance',
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
    :'userAdminID'
), (
    true,
    :'allianceID',
    'groups-manager',
    :'userGroupsManagerID'
), (
    true,
    :'allianceID',
    'viewer',
    :'userViewerID'
), (
    false,
    :'allianceID',
    'admin',
    :'userPendingAdminID'
), (
    true,
    :'otherAllianceID',
    'admin',
    :'userRegularID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep tested alliance permissions aligned with canonical catalog
with tested_permissions (
    permission
) as (
    values
        ('alliance.groups.write'),
        ('alliance.read'),
        ('alliance.settings.write'),
        ('alliance.taxonomy.write'),
        ('alliance.team.write')
)
select is(
    (
        select count(*)
        from (
            (
                select alliance_permission_id
                from alliance_permission
                except
                select permission
                from tested_permissions
            )
            union all
            (
                select permission
                from tested_permissions
                except
                select alliance_permission_id
                from alliance_permission
            )
        ) mismatches
    ),
    0::bigint,
    'Tested alliance permissions should match the canonical catalog'
);

-- Should enforce the full alliance role-permission matrix
with actors (
    actor,
    alliance_id,
    user_id,
    allowed_permissions
) as (
    values
        (
            'admin',
            :'allianceID'::uuid,
            :'userAdminID'::uuid,
            array[
                'alliance.groups.write',
                'alliance.read',
                'alliance.settings.write',
                'alliance.taxonomy.write',
                'alliance.team.write'
            ]::text[]
        ),
        (
            'admin-wrong-alliance',
            :'otherAllianceID'::uuid,
            :'userAdminID'::uuid,
            array[]::text[]
        ),
        (
            'groups-manager',
            :'allianceID'::uuid,
            :'userGroupsManagerID'::uuid,
            array[
                'alliance.groups.write',
                'alliance.read'
            ]::text[]
        ),
        (
            'pending-admin',
            :'allianceID'::uuid,
            :'userPendingAdminID'::uuid,
            array[]::text[]
        ),
        (
            'regular-user',
            :'allianceID'::uuid,
            :'userRegularID'::uuid,
            array[]::text[]
        ),
        (
            'regular-user-other-alliance-admin',
            :'otherAllianceID'::uuid,
            :'userRegularID'::uuid,
            array[
                'alliance.groups.write',
                'alliance.read',
                'alliance.settings.write',
                'alliance.taxonomy.write',
                'alliance.team.write'
            ]::text[]
        ),
        (
            'viewer',
            :'allianceID'::uuid,
            :'userViewerID'::uuid,
            array[
                'alliance.read'
            ]::text[]
        )
), permissions (
    permission
) as (
    values
        ('alliance.groups.write'),
        ('alliance.read'),
        ('alliance.settings.write'),
        ('alliance.taxonomy.write'),
        ('alliance.team.write'),
        ('alliance.unknown')
), test_cases as (
    select
        a.actor,
        a.alliance_id,
        a.user_id,
        p.permission,
        p.permission = any (a.allowed_permissions) as expected
    from actors a
    cross join permissions p
)
select is(
    user_has_alliance_permission(alliance_id, user_id, permission),
    expected,
    format(
        'Actor=%s user_id=%s alliance_id=%s permission=%s should be %s',
        actor,
        user_id,
        alliance_id,
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
