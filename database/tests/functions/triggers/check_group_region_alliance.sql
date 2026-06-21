-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000010'
\set alliance1ID '00000000-0000-0000-0000-000000000001'
\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set groupID '00000000-0000-0000-0000-000000000051'
\set region1ID '00000000-0000-0000-0000-000000000030'
\set region2ID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance 1
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'alliance1ID', 'alliance-1', 'Alliance 1', 'Test alliance 1', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Alliance 2
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'alliance2ID', 'alliance-2', 'Alliance 2', 'Test alliance 2', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category (belongs to alliance 1)
insert into group_category (group_category_id, name, alliance_id)
values (:'categoryID', 'Technology', :'alliance1ID');

-- Region 1 (belongs to alliance 1)
insert into region (region_id, name, alliance_id)
values (:'region1ID', 'North America', :'alliance1ID');

-- Region 2 (belongs to alliance 2)
insert into region (region_id, name, alliance_id)
values (:'region2ID', 'Europe', :'alliance2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when group has no region (null)
select lives_ok(
    format('insert into "group" (group_id, alliance_id, name, slug, description, group_category_id, region_id) values (%L, %L, %L, %L, %L, %L, NULL)',
        :'groupID', :'alliance1ID', 'Test Group', 'test-group', 'A test group', :'categoryID'),
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
        gen_random_uuid(), :'alliance1ID', 'Another Group', 'another-group', 'Another test group', :'categoryID', :'region2ID'),
    'region not found in alliance',
    'Should fail when inserting group with region from different alliance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
