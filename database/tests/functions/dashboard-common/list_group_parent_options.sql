-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adminParentID '1c070000-0000-0000-0000-000000000001'
\set childCandidateID '1c070000-0000-0000-0000-000000000002'
\set communityID '1c070000-0000-0000-0000-000000000003'
\set currentGroupID '1c070000-0000-0000-0000-000000000004'
\set deletedGroupID '1c070000-0000-0000-0000-000000000005'
\set groupAdminID '1c070000-0000-0000-0000-000000000006'
\set groupCategoryID '1c070000-0000-0000-0000-000000000007'
\set noPermissionUserID '1c070000-0000-0000-0000-000000000009'
\set otherCommunityGroupID '1c070000-0000-0000-0000-00000000000a'
\set otherCommunityID '1c070000-0000-0000-0000-00000000000b'
\set otherGroupCategoryID '1c070000-0000-0000-0000-00000000000c'
\set parentWithChildID '1c070000-0000-0000-0000-00000000000d'
\set parentWithoutPermissionID '1c070000-0000-0000-0000-000000000008'
\set subgroupID '1c070000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group category, users and groups
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'otherGroupCategoryID', :'otherCommunityID');
select fx_user(:'groupAdminID');
select fx_user(:'noPermissionUserID');
select fx_group(:'otherCommunityGroupID', :'otherCommunityID', :'otherGroupCategoryID');

select fx_group(:'adminParentID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Admin Parent'));
-- group
select fx_group(:'currentGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Current Group'));
-- group
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));
-- group
select fx_group(:'parentWithChildID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Parent With Child'));
-- group
select fx_group(:'parentWithoutPermissionID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Parent Without Permission'));

-- Child groups
select fx_group(:'childCandidateID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'parentWithoutPermissionID'));
-- group
select fx_group(:'subgroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'adminParentID'));

-- Group team
insert into group_team (group_id, user_id, role, accepted) values
    (:'adminParentID', :'groupAdminID', 'admin', true),
    (:'currentGroupID', :'groupAdminID', 'admin', true),
    (:'parentWithChildID', :'groupAdminID', 'admin', true),
    (:'subgroupID', :'groupAdminID', 'admin', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list active top-level parent options managed by the user
select is(
    list_group_parent_options(:'communityID'::uuid, :'groupAdminID'::uuid, :'currentGroupID'::uuid)::jsonb,
    format(
        $json$
        [
            {
                "active": true,
                "group_id": "%s",
                "is_current": false,
                "is_selectable": true,
                "name": "Admin Parent"
            },
            {
                "active": true,
                "group_id": "%s",
                "is_current": false,
                "is_selectable": true,
                "name": "Parent With Child"
            }
        ]
        $json$,
        :'adminParentID',
        :'parentWithChildID'
    )::jsonb,
    'Should list active top-level parent options managed by the user'
);

-- Should return no selectable options for a user without parent permissions
select is(
    list_group_parent_options(:'communityID'::uuid, :'noPermissionUserID'::uuid, :'currentGroupID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return no selectable options for a user without parent permissions'
);

-- Should support add forms where there is no current group to exclude
select is(
    list_group_parent_options(:'communityID'::uuid, :'groupAdminID'::uuid, null::uuid)::jsonb,
    format(
        $json$
        [
            {
                "active": true,
                "group_id": "%s",
                "is_current": false,
                "is_selectable": true,
                "name": "Admin Parent"
            },
            {
                "active": true,
                "group_id": "%s",
                "is_current": false,
                "is_selectable": true,
                "name": "Current Group"
            },
            {
                "active": true,
                "group_id": "%s",
                "is_current": false,
                "is_selectable": true,
                "name": "Parent With Child"
            }
        ]
        $json$,
        :'adminParentID',
        :'currentGroupID',
        :'parentWithChildID'
    )::jsonb,
    'Should support add forms where there is no current group to exclude'
);

-- Should include the current parent when the user cannot select it
select is(
    list_group_parent_options(:'communityID'::uuid, :'noPermissionUserID'::uuid, :'childCandidateID'::uuid)::jsonb,
    format(
        $json$
        [
            {
                "active": true,
                "group_id": "%s",
                "is_current": true,
                "is_selectable": false,
                "name": "Parent Without Permission"
            }
        ]
        $json$,
        :'parentWithoutPermissionID'
    )::jsonb,
    'Should include the current parent when the user cannot select it'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
