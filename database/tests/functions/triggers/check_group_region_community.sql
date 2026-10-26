-- Tests that group regions belong to the community of the group.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID 'ab060000-0000-0000-0000-000000000001'
\set community2ID 'ab060000-0000-0000-0000-000000000002'
\set crossCommunityGroupID 'ab060000-0000-0000-0000-000000000005'
\set crossCommunityUpdateGroupID 'ab060000-0000-0000-0000-000000000008'
\set groupCategoryID 'ab060000-0000-0000-0000-000000000003'
\set groupID 'ab060000-0000-0000-0000-000000000004'
\set region1ID 'ab060000-0000-0000-0000-000000000006'
\set region2ID 'ab060000-0000-0000-0000-000000000007'
\set sameCommunityUpdateGroupID 'ab060000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and group category
select fx_community(:'community1ID');
select fx_community(:'community2ID');
select fx_group_category(:'groupCategoryID', :'community1ID');

-- Group without a region that is moved to another community's region
select fx_group(:'crossCommunityUpdateGroupID', :'community1ID', :'groupCategoryID');

-- Group without a region that is moved to its own community's region
select fx_group(:'sameCommunityUpdateGroupID', :'community1ID', :'groupCategoryID');

-- Region 1 (belongs to community 1)
insert into region (region_id, community_id, name)
values (:'region1ID', :'community1ID', 'North America');

-- Region 2 (belongs to community 2)
insert into region (region_id, community_id, name)
values (:'region2ID', :'community2ID', 'Europe');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when group has no region (null)
select lives_ok(
    format('insert into "group" (group_id, community_id, name, slug, description, group_category_id, region_id) values (%L, %L, %L, %L, %L, %L, NULL)',
        :'groupID', :'community1ID', 'Test Group', 'test-group', 'A test group', :'groupCategoryID'),
    'Should succeed when group has no region (null)'
);

-- Should succeed when region is from same community as group
select lives_ok(
    format('update "group" set region_id = %L where group_id = %L', :'region1ID', :'sameCommunityUpdateGroupID'),
    'Should succeed when region is from same community as group'
);

-- Should fail when region is from different community
select throws_ok(
    format('update "group" set region_id = %L where group_id = %L', :'region2ID', :'crossCommunityUpdateGroupID'),
    'OCG01',
    'region not found in community',
    'Should fail when region is from different community'
);

-- Should fail when inserting group with region from different community
select throws_ok(
    format('insert into "group" (group_id, community_id, name, slug, description, group_category_id, region_id) values (%L, %L, %L, %L, %L, %L, %L)',
        :'crossCommunityGroupID', :'community1ID', 'Another Group', 'another-group', 'Another test group', :'groupCategoryID', :'region2ID'),
    'OCG01',
    'region not found in community',
    'Should fail when inserting group with region from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
