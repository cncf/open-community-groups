-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '8c200000-0000-0000-0000-000000000002'
\set community2ID '8c200000-0000-0000-0000-000000000003'
\set deletedParentID '8c200000-0000-0000-0000-000000000004'
\set group1ID '8c200000-0000-0000-0000-000000000005'
\set group2ID '8c200000-0000-0000-0000-000000000006'
\set group3ID '8c200000-0000-0000-0000-000000000007'
\set group4ID '8c200000-0000-0000-0000-000000000008'
\set groupCategory1ID '8c200000-0000-0000-0000-000000000009'
\set groupCategory2ID '8c200000-0000-0000-0000-00000000000a'
\set inactiveParentID '8c200000-0000-0000-0000-00000000000c'
\set otherCommunityGroupID '8c200000-0000-0000-0000-00000000000d'

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
        :'community1ID',
        'test-community',
        'Test Community',
        'Test community',
        'https://example.com/banner-mobile.png',
        'https://example.com/banner.png',
        'https://example.com/logo.png'
    ), (
        :'community2ID',
        'other-community',
        'Other Community',
        'Other community',
        'https://example.com/other-banner-mobile.png',
        'https://example.com/other-banner.png',
        'https://example.com/other-logo.png'
    );

-- Group categories
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategory1ID', :'community1ID', 'Technology'),
    (:'groupCategory2ID', :'community2ID', 'Technology');

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
    (:'deletedParentID', :'community1ID', :'groupCategory1ID', 'Deleted Parent', 'deleted-parent', false, true),
    (:'group1ID', :'community1ID', :'groupCategory1ID', 'Group One', 'group-one', true, false),
    (:'group3ID', :'community1ID', :'groupCategory1ID', 'Group Three', 'group-three', true, false),
    (:'group4ID', :'community1ID', :'groupCategory1ID', 'Group Four', 'group-four', true, false),
    (:'inactiveParentID', :'community1ID', :'groupCategory1ID', 'Inactive Parent', 'inactive-parent', false, false),
    (
        :'otherCommunityGroupID',
        :'community2ID',
        :'groupCategory2ID',
        'Other Community Group',
        'other-community-group',
        true,
        false
    );

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
        :'group2ID',
        :'community1ID',
        :'groupCategory1ID',
        'Group Two',
        'group-two',
        true,
        false,

        :'group1ID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject self-parenting
select throws_ok(
    format(
        $$update "group" set parent_group_id = %L::uuid where group_id = %L::uuid$$,
        :'group1ID',
        :'group1ID'
    ),
    'group cannot be its own parent',
    'Should reject self-parenting'
);

-- Should reject cross-community parents
select throws_ok(
    format(
        $$update "group" set parent_group_id = %L::uuid where group_id = %L::uuid$$,
        :'otherCommunityGroupID',
        :'group1ID'
    ),
    'parent group must belong to the same community',
    'Should reject cross-community parents'
);

-- Should reject deleted parents
select throws_ok(
    format(
        $$update "group" set parent_group_id = %L::uuid where group_id = %L::uuid$$,
        :'deletedParentID',
        :'group1ID'
    ),
    'parent group cannot be deleted',
    'Should reject deleted parents'
);

-- Should reject newly selected inactive parents
select throws_ok(
    format(
        $$update "group" set parent_group_id = %L::uuid where group_id = %L::uuid$$,
        :'inactiveParentID',
        :'group1ID'
    ),
    'parent group must be active',
    'Should reject newly selected inactive parents'
);

-- Should reject assigning a subgroup as a parent
select throws_ok(
    format(
        $$update "group" set parent_group_id = %L::uuid where group_id = %L::uuid$$,
        :'group2ID',
        :'group3ID'
    ),
    'parent group cannot be a subgroup',
    'Should reject assigning a subgroup as a parent'
);

-- Should reject assigning a parent to a group with child links
select throws_ok(
    format(
        $$update "group" set parent_group_id = %L::uuid where group_id = %L::uuid$$,
        :'group3ID',
        :'group1ID'
    ),
    'group with subgroups cannot have a parent',
    'Should reject assigning a parent to a group with child links'
);

-- Should allow multiple children under one parent
select lives_ok(
    format(
        $$update "group" set parent_group_id = %L::uuid where group_id = %L::uuid$$,
        :'group1ID',
        :'group4ID'
    ),
    'Should allow multiple children under one parent'
);

-- Should preserve an unchanged parent link
select lives_ok(
    format(
        $$update "group" set parent_group_id = %L::uuid where group_id = %L::uuid$$,
        :'group1ID',
        :'group2ID'
    ),
    'Should preserve an unchanged parent link'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
