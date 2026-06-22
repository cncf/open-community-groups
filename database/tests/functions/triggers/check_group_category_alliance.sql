-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID 'ab050000-0000-0000-0000-000000000001'
\set alliance2ID 'ab050000-0000-0000-0000-000000000002'
\set groupCategory1ID 'ab050000-0000-0000-0000-000000000003'
\set groupCategory2ID 'ab050000-0000-0000-0000-000000000004'
\set groupID 'ab050000-0000-0000-0000-000000000005'
\set missingGroupID 'ab050000-0000-0000-0000-000000000006'

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

-- Group Category 1 (belongs to alliance 1)
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategory1ID', :'alliance1ID', 'Technology');

-- Group Category 2 (belongs to alliance 2)
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategory2ID', :'alliance2ID', 'Business');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when group category is from same alliance as group
select lives_ok(
    format('insert into "group" (group_id, alliance_id, name, slug, description, group_category_id) values (%L, %L, %L, %L, %L, %L)',
        :'groupID', :'alliance1ID', 'Test Group', 'test-group', 'A test group', :'groupCategory1ID'),
    'Should succeed when group category is from same alliance as group'
);

-- Should fail when group category is from different alliance
select throws_ok(
    format('insert into "group" (group_id, alliance_id, name, slug, description, group_category_id) values (%L, %L, %L, %L, %L, %L)',
        :'missingGroupID', :'alliance1ID', 'Another Group', 'another-group', 'Another test group', :'groupCategory2ID'),
    'group category not found in alliance',
    'Should fail when group category is from different alliance'
);

-- Should fail when updating group to category from different alliance
select throws_ok(
    format('update "group" set group_category_id = %L where group_id = %L', :'groupCategory2ID', :'groupID'),
    'group category not found in alliance',
    'Should fail when updating group to category from different alliance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
