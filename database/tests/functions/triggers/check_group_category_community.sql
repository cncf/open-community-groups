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
\set groupCategory1ID 'ab050000-0000-0000-0000-000000000003'
\set groupCategory2ID 'ab050000-0000-0000-0000-000000000004'
\set groupID 'ab050000-0000-0000-0000-000000000005'
\set missingGroupID 'ab050000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community
select fx_community(:'community1ID');
select fx_community(:'community2ID');

-- Group Category 1 (belongs to community 1)
insert into group_category (group_category_id, community_id, name)
values (:'groupCategory1ID', :'community1ID', 'Technology');

-- Group Category 2 (belongs to community 2)
insert into group_category (group_category_id, community_id, name)
values (:'groupCategory2ID', :'community2ID', 'Business');

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
        :'missingGroupID', :'community1ID', 'Another Group', 'another-group', 'Another test group', :'groupCategory2ID'),
    'OCG01',
    'group category not found in community',
    'Should fail when group category is from different community'
);

-- Should fail when updating group to category from different community
select throws_ok(
    format('update "group" set group_category_id = %L where group_id = %L', :'groupCategory2ID', :'groupID'),
    'OCG01',
    'group category not found in community',
    'Should fail when updating group to category from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
