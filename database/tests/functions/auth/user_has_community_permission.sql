-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(43);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0a090000-0000-0000-0000-000000000001'
\set otherCommunityID '0a090000-0000-0000-0000-000000000002'
\set userAdminID '0a090000-0000-0000-0000-000000000003'
\set userGroupsManagerID '0a090000-0000-0000-0000-000000000004'
\set userPendingAdminID '0a090000-0000-0000-0000-000000000005'
\set userRegularID '0a090000-0000-0000-0000-000000000006'
\set userViewerID '0a090000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and users for permission checks
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_user(:'userAdminID');
select fx_user(:'userGroupsManagerID');
select fx_user(:'userPendingAdminID');
select fx_user(:'userRegularID');
select fx_user(:'userViewerID');

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
