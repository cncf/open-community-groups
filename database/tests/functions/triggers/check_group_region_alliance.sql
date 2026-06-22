-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID 'ab060000-0000-0000-0000-000000000001'
\set alliance2ID 'ab060000-0000-0000-0000-000000000002'
\set groupCategoryID 'ab060000-0000-0000-0000-000000000003'
\set groupID 'ab060000-0000-0000-0000-000000000004'
\set missingGroupID 'ab060000-0000-0000-0000-000000000005'
\set region1ID 'ab060000-0000-0000-0000-000000000006'
\set region2ID 'ab060000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance 1
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'alliance1ID',
    'alliance-1',
    'Alliance 1',
    'Test alliance 1',
    'https://example.com/banner-mobile-1.png',
    'https://example.com/banner-1.png',
    'https://example.com/logo-1.png'
);

-- Alliance 2
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'alliance2ID',
    'alliance-2',
    'Alliance 2',
    'Test alliance 2',
    'https://example.com/banner-mobile-2.png',
    'https://example.com/banner-2.png',
    'https://example.com/logo-2.png'
);

-- Group Category (belongs to alliance 1)
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'alliance1ID', 'Technology');

-- Region 1 (belongs to alliance 1)
insert into region (region_id, alliance_id, name)
values (:'region1ID', :'alliance1ID', 'North America');

-- Region 2 (belongs to alliance 2)
insert into region (region_id, alliance_id, name)
values (:'region2ID', :'alliance2ID', 'Europe');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when group has no region (null)
select lives_ok(
    format('insert into "group" (group_id, alliance_id, name, slug, description, group_category_id, region_id) values (%L, %L, %L, %L, %L, %L, NULL)',
        :'groupID', :'alliance1ID', 'Test Group', 'test-group', 'A test group', :'groupCategoryID'),
    'Should succeed when group has no region (null)'
);

-- Should succeed when region is from same alliance as group
select lives_ok(
    format('update "group" set region_id = %L where group_id = %L', :'region1ID', :'groupID'),
    'Should succeed when region is from same alliance as group'
);

-- Should fail when region is from different alliance
select throws_ok(
    format('update "group" set region_id = %L where group_id = %L', :'region2ID', :'groupID'),
    'region not found in alliance',
    'Should fail when region is from different alliance'
);

-- Should fail when inserting group with region from different alliance
select throws_ok(
    format('insert into "group" (group_id, alliance_id, name, slug, description, group_category_id, region_id) values (%L, %L, %L, %L, %L, %L, %L)',
        :'missingGroupID', :'alliance1ID', 'Another Group', 'another-group', 'Another test group', :'groupCategoryID', :'region2ID'),
    'region not found in alliance',
    'Should fail when inserting group with region from different alliance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
