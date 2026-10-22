-- Tests that group categories belong to the community of the group.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID 'ab050000-0000-0000-0000-000000000001'
\set community2ID 'ab050000-0000-0000-0000-000000000002'
\set crossCommunityGroupID 'ab050000-0000-0000-0000-000000000006'
\set existingGroupID 'ab050000-0000-0000-0000-000000000007'
\set groupCategory1ID 'ab050000-0000-0000-0000-000000000003'
\set groupCategory2ID 'ab050000-0000-0000-0000-000000000004'
\set groupID 'ab050000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities
select fx_community(:'community1ID');
select fx_community(:'community2ID');

-- Group category of community 1
select fx_group_category(:'groupCategory1ID', :'community1ID');

-- Group category of community 2
select fx_group_category(:'groupCategory2ID', :'community2ID');

-- Existing group whose category is moved to another community
select fx_group(:'existingGroupID', :'community1ID', :'groupCategory1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when group category is from same community as group
select lives_ok(
    format('insert into "group" (group_id, community_id, name, slug, description, group_category_id) values (%L, %L, %L, %L, %L, %L)',
        :'groupID', :'community1ID', 'Test Group', 'test-group', 'A test group', :'groupCategory1ID'),
    'Should succeed when group category is from same community as group'
);

-- Should fail when group category is from different community
select throws_ok(
    format('insert into "group" (group_id, community_id, name, slug, description, group_category_id) values (%L, %L, %L, %L, %L, %L)',
        :'crossCommunityGroupID', :'community1ID', 'Another Group', 'another-group', 'Another test group', :'groupCategory2ID'),
    'OCG01',
    'group category not found in community',
    'Should fail when group category is from different community'
);

-- Should fail when updating group to category from different community
select throws_ok(
    format('update "group" set group_category_id = %L where group_id = %L', :'groupCategory2ID', :'existingGroupID'),
    'OCG01',
    'group category not found in community',
    'Should fail when updating group to category from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
