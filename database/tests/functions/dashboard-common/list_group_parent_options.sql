-- Tests listing selectable and current parent group options.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adminParentID '1c070000-0000-0000-0000-000000000001'
\set childCandidateID '1c070000-0000-0000-0000-000000000002'
\set communityID '1c070000-0000-0000-0000-000000000003'
\set currentGroupID '1c070000-0000-0000-0000-000000000004'
\set groupAdminID '1c070000-0000-0000-0000-000000000006'
\set groupCategoryID '1c070000-0000-0000-0000-000000000007'
\set inactiveParentChildID '1c070000-0000-0000-0000-000000000010'
\set inactiveParentID '1c070000-0000-0000-0000-00000000000f'
\set noPermissionUserID '1c070000-0000-0000-0000-000000000009'
\set parentWithoutPermissionID '1c070000-0000-0000-0000-000000000008'
\set secondAdminParentID '1c070000-0000-0000-0000-00000000000d'
\set subgroupID '1c070000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group admin user
select fx_user(:'groupAdminID');

-- User without group permissions
select fx_user(:'noPermissionUserID');

-- Active top-level group the admin manages
select fx_group(:'adminParentID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Admin Parent'));

-- Active top-level group being edited
select fx_group(:'currentGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Current Group'));

-- Top-level group the admin manages, inactivated after its child is linked
select fx_group(:'inactiveParentID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Inactive Parent'));

-- Active top-level group without an admin team member
select fx_group(:'parentWithoutPermissionID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Parent Without Permission'));

-- Second active top-level group the admin manages
select fx_group(:'secondAdminParentID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Second Admin Parent'));

-- Child of the group without an admin team member
select fx_group(:'childCandidateID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'parentWithoutPermissionID'));

-- Child of the inactive group
select fx_group(:'inactiveParentChildID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'inactiveParentID'));

-- Child of the admin parent
select fx_group(:'subgroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'adminParentID'));

-- Inactivate the parent after linking its child, because the parent trigger rejects inactive parents on insert
update "group"
set active = false
where group_id = :'inactiveParentID';

-- Group admin memberships
insert into group_team (group_id, user_id, role, accepted) values
    (:'adminParentID', :'groupAdminID', 'admin', true),
    (:'currentGroupID', :'groupAdminID', 'admin', true),
    (:'inactiveParentID', :'groupAdminID', 'admin', true),
    (:'secondAdminParentID', :'groupAdminID', 'admin', true),
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
                "name": "Second Admin Parent"
            }
        ]
        $json$,
        :'adminParentID',
        :'secondAdminParentID'
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
                "name": "Second Admin Parent"
            }
        ]
        $json$,
        :'adminParentID',
        :'currentGroupID',
        :'secondAdminParentID'
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

-- Should include an inactive current parent as a non-selectable option
select is(
    list_group_parent_options(:'communityID'::uuid, :'groupAdminID'::uuid, :'inactiveParentChildID'::uuid)::jsonb,
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
                "name": "Second Admin Parent"
            },
            {
                "active": false,
                "group_id": "%s",
                "is_current": true,
                "is_selectable": false,
                "name": "Inactive Parent"
            }
        ]
        $json$,
        :'adminParentID',
        :'currentGroupID',
        :'secondAdminParentID',
        :'inactiveParentID'
    )::jsonb,
    'Should include an inactive current parent as a non-selectable option'
);

-- Should list a selectable current parent once as a selectable option
select is(
    list_group_parent_options(:'communityID'::uuid, :'groupAdminID'::uuid, :'subgroupID'::uuid)::jsonb,
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
                "name": "Second Admin Parent"
            }
        ]
        $json$,
        :'adminParentID',
        :'currentGroupID',
        :'secondAdminParentID'
    )::jsonb,
    'Should list a selectable current parent once as a selectable option'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
