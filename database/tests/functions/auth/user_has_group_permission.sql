-- Tests group permission evaluation across community and group roles.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(176);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0a100000-0000-0000-0000-000000000001'
\set deletedGroupID '0a100000-0000-0000-0000-000000000002'
\set groupCategoryID '0a100000-0000-0000-0000-000000000003'
\set groupID '0a100000-0000-0000-0000-000000000004'
\set otherCommunityGroupID '0a100000-0000-0000-0000-000000000005'
\set otherCommunityID '0a100000-0000-0000-0000-000000000006'
\set otherGroupCategoryID '0a100000-0000-0000-0000-000000000007'
\set otherGroupID '0a100000-0000-0000-0000-000000000008'
\set restrictedCommunityID '0a100000-0000-0000-0000-000000000009'
\set restrictedGroupCategoryID '0a100000-0000-0000-0000-000000000010'
\set restrictedGroupID '0a100000-0000-0000-0000-000000000011'
\set userCheckInManagerID '0a100000-0000-0000-0000-000000000023'
\set userCommunityAdminID '0a100000-0000-0000-0000-000000000012'
\set userCommunityGroupsManagerID '0a100000-0000-0000-0000-000000000013'
\set userCommunityPendingGroupsManagerID '0a100000-0000-0000-0000-000000000014'
\set userCommunityViewerID '0a100000-0000-0000-0000-000000000015'
\set userDualRoleID '0a100000-0000-0000-0000-000000000016'
\set userEventsManagerID '0a100000-0000-0000-0000-000000000017'
\set userGroupAdminID '0a100000-0000-0000-0000-000000000018'
\set userGroupViewerID '0a100000-0000-0000-0000-000000000019'
\set userOtherGroupAdminID '0a100000-0000-0000-0000-000000000020'
\set userPendingGroupAdminID '0a100000-0000-0000-0000-000000000021'
\set userRegularID '0a100000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, categories, users and groups for permission checks
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'otherGroupCategoryID', :'otherCommunityID');
select fx_user(:'userCheckInManagerID');
select fx_user(:'userCommunityAdminID');
select fx_user(:'userCommunityGroupsManagerID');
select fx_user(:'userCommunityPendingGroupsManagerID');
select fx_user(:'userCommunityViewerID');
select fx_user(:'userDualRoleID');
select fx_user(:'userEventsManagerID');
select fx_user(:'userGroupAdminID');
select fx_user(:'userGroupViewerID');
select fx_user(:'userOtherGroupAdminID');
select fx_user(:'userPendingGroupAdminID');
select fx_user(:'userRegularID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherCommunityGroupID', :'otherCommunityID', :'otherGroupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Restricted community used for group-team management checks
select fx_community(:'restrictedCommunityID', jsonb_build_object('group_team_management_restricted', true));
select fx_group_category(:'restrictedGroupCategoryID', :'restrictedCommunityID');
select fx_group(:'restrictedGroupID', :'restrictedCommunityID', :'restrictedGroupCategoryID');

-- Deleted group used for inactive permission checks
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Group team memberships
insert into group_team (
    accepted,
    group_id,
    role,
    user_id
) values (
    true,
    :'groupID',
    'check-in-manager',
    :'userCheckInManagerID'
), (
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
        ('group.badges.write'),
        ('group.check-ins.write'),
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
            'check-in-manager',
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userCheckInManagerID'::uuid,
            array[
                'group.check-ins.write',
                'group.read'
            ]::text[]
        ),
        (
            'community-admin',
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'userCommunityAdminID'::uuid,
            array[
                'group.badges.write',
                'group.check-ins.write',
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
                'group.badges.write',
                'group.check-ins.write',
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
                'group.badges.write',
                'group.check-ins.write',
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
                'group.badges.write',
                'group.check-ins.write',
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
                'group.badges.write',
                'group.check-ins.write',
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
                'group.badges.write',
                'group.check-ins.write',
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
                'group.badges.write',
                'group.check-ins.write',
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
        ('group.badges.write'),
        ('group.check-ins.write'),
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
