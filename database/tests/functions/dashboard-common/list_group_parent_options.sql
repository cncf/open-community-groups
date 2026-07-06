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

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values
    (
        :'communityID',
        'parent-options-community',
        'Parent Options Community',
        'Community for parent option tests',
        'https://example.com/banner-mobile.png',
        'https://example.com/banner.png',
        'https://example.com/logo.png'
    ),
    (
        :'otherCommunityID',
        'other-parent-options-community',
        'Other Parent Options Community',
        'Other community for parent option tests',
        'https://example.com/other-banner-mobile.png',
        'https://example.com/other-banner.png',
        'https://example.com/other-logo.png'
    );

-- Group categories
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Technology'),
    (:'otherGroupCategoryID', :'otherCommunityID', 'Technology');

-- Users
insert into "user" (user_id, auth_hash, email, username) values
    (:'groupAdminID', 'hash-1', 'group-admin@example.com', 'group-admin'),
    (:'noPermissionUserID', 'hash-2', 'no-permission@example.com', 'no-permission');

-- Parent candidate groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values
    (:'adminParentID', :'communityID', :'groupCategoryID', 'Admin Parent', 'admin-parent', true, false),
    (:'currentGroupID', :'communityID', :'groupCategoryID', 'Current Group', 'current-group', true, false),
    (:'deletedGroupID', :'communityID', :'groupCategoryID', 'Deleted Parent', 'deleted-parent', false, true),
    (:'otherCommunityGroupID', :'otherCommunityID', :'otherGroupCategoryID', 'Other Community Group', 'other-community-group', true, false),
    (:'parentWithChildID', :'communityID', :'groupCategoryID', 'Parent With Child', 'parent-with-child', true, false),
    (:'parentWithoutPermissionID', :'communityID', :'groupCategoryID', 'Parent Without Permission', 'parent-without-permission', true, false);

-- Child groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted,

    parent_group_id
) values
    (
        :'childCandidateID',
        :'communityID',
        :'groupCategoryID',
        'Child Candidate',
        'child-candidate',
        true,
        false,

        :'parentWithoutPermissionID'
    ),
    (
        :'subgroupID',
        :'communityID',
        :'groupCategoryID',
        'Existing Subgroup',
        'existing-subgroup',
        true,
        false,

        :'adminParentID'
    );

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
