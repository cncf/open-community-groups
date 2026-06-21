-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000010'
\set category2ID '00000000-0000-0000-0000-000000000011'
\set alliance1ID '00000000-0000-0000-0000-000000000001'
\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set groupID '00000000-0000-0000-0000-000000000051'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance 1
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'alliance1ID', 'alliance-1', 'Alliance 1', 'Test alliance 1', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Alliance 2
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'alliance2ID', 'alliance-2', 'Alliance 2', 'Test alliance 2', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category 1 (belongs to alliance 1)
insert into group_category (group_category_id, name, alliance_id)
values (:'category1ID', 'Technology', :'alliance1ID');

-- Group Category 2 (belongs to alliance 2)
insert into group_category (group_category_id, name, alliance_id)
values (:'category2ID', 'Business', :'alliance2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when group category is from same alliance as group
select lives_ok(
    format('insert into "group" (group_id, alliance_id, name, slug, description, group_category_id) values (%L, %L, %L, %L, %L, %L)',
        :'groupID', :'alliance1ID', 'Test Group', 'test-group', 'A test group', :'category1ID'),
    'Should succeed when group category is from same alliance as group'
);

-- Should fail when group category is from different alliance
select throws_ok(
    format('insert into "group" (group_id, alliance_id, name, slug, description, group_category_id) values (%L, %L, %L, %L, %L, %L)',
        gen_random_uuid(), :'alliance1ID', 'Another Group', 'another-group', 'Another test group', :'category2ID'),
    'group category not found in alliance',
    'Should fail when group category is from different alliance'
);

-- Should fail when updating group to category from different alliance
select throws_ok(
    format('update "group" set group_category_id = %L where group_id = %L', :'category2ID', :'groupID'),
    'group category not found in alliance',
    'Should fail when updating group to category from different alliance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
