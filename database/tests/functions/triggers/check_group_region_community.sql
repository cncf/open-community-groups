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
\set groupCategoryID 'ab060000-0000-0000-0000-000000000003'
\set groupID 'ab060000-0000-0000-0000-000000000004'
\set missingGroupID 'ab060000-0000-0000-0000-000000000005'
\set region1ID 'ab060000-0000-0000-0000-000000000006'
\set region2ID 'ab060000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community 1
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'community1ID',
    'community-1',
    'Community 1',
    'Test community 1',
    'https://example.com/banner-mobile-1.png',
    'https://example.com/banner-1.png',
    'https://example.com/logo-1.png'
);

-- Community 2
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'community2ID',
    'community-2',
    'Community 2',
    'Test community 2',
    'https://example.com/banner-mobile-2.png',
    'https://example.com/banner-2.png',
    'https://example.com/logo-2.png'
);

-- Group Category (belongs to community 1)
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'community1ID', 'Technology');

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
    format('update "group" set region_id = %L where group_id = %L', :'region1ID', :'groupID'),
    'Should succeed when region is from same community as group'
);

-- Should fail when region is from different community
select throws_ok(
    format('update "group" set region_id = %L where group_id = %L', :'region2ID', :'groupID'),
    'region not found in community',
    'Should fail when region is from different community'
);

-- Should fail when inserting group with region from different community
select throws_ok(
    format('insert into "group" (group_id, community_id, name, slug, description, group_category_id, region_id) values (%L, %L, %L, %L, %L, %L, %L)',
        :'missingGroupID', :'community1ID', 'Another Group', 'another-group', 'Another test group', :'groupCategoryID', :'region2ID'),
    'region not found in community',
    'Should fail when inserting group with region from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
