-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set alliance1ID '00000000-0000-0000-0000-000000000001'
\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set eventID '00000000-0000-0000-0000-000000000101'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
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

-- Event Category 1 (belongs to alliance 1)
insert into event_category (event_category_id, name, alliance_id)
values (:'category1ID', 'Conference', :'alliance1ID');

-- Event Category 2 (belongs to alliance 2)
insert into event_category (event_category_id, name, alliance_id)
values (:'category2ID', 'Workshop', :'alliance2ID');

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values (:'groupCategoryID', 'Technology', :'alliance1ID');

-- Group (belongs to alliance 1)
insert into "group" (
    group_id,
    alliance_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'alliance1ID',
    'Test Group',
    'test-group',
    'A test group',
    :'groupCategoryID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when event category is from same alliance as group
select lives_ok(
    format('insert into event (event_id, group_id, name, slug, description, timezone, event_category_id, event_kind_id) values (%L, %L, %L, %L, %L, %L, %L, %L)',
        :'eventID', :'groupID', 'Test Event', 'test-event', 'A test event', 'UTC', :'category1ID', 'in-person'),
    'Should succeed when event category is from same alliance as group'
);

-- Should fail when event category is from different alliance
select throws_ok(
    format('insert into event (event_id, group_id, name, slug, description, timezone, event_category_id, event_kind_id) values (%L, %L, %L, %L, %L, %L, %L, %L)',
        gen_random_uuid(), :'groupID', 'Another Event', 'another-event', 'Another test event', 'UTC', :'category2ID', 'in-person'),
    'event category not found in alliance',
    'Should fail when event category is from different alliance'
);

-- Should fail when updating event to category from different alliance
select throws_ok(
    format('update event set event_category_id = %L where event_id = %L', :'category2ID', :'eventID'),
    'event category not found in alliance',
    'Should fail when updating event to category from different alliance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
