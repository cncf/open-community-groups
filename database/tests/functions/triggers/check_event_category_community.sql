-- Tests that event categories belong to the community of the event group.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID 'ab020000-0000-0000-0000-000000000001'
\set community2ID 'ab020000-0000-0000-0000-000000000002'
\set crossCommunityEventID 'ab020000-0000-0000-0000-000000000008'
\set eventCategory1ID 'ab020000-0000-0000-0000-000000000003'
\set eventCategory2ID 'ab020000-0000-0000-0000-000000000004'
\set eventID 'ab020000-0000-0000-0000-000000000005'
\set existingEventID 'ab020000-0000-0000-0000-000000000009'
\set groupCategoryID 'ab020000-0000-0000-0000-000000000006'
\set groupID 'ab020000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities
select fx_community(:'community1ID');
select fx_community(:'community2ID');

-- Event category of community 1
select fx_event_category(:'eventCategory1ID', :'community1ID');

-- Event category of community 2
select fx_event_category(:'eventCategory2ID', :'community2ID');

-- Baseline group category and group of community 1
select fx_group_category(:'groupCategoryID', :'community1ID');
select fx_group(:'groupID', :'community1ID', :'groupCategoryID');

-- Existing event whose category is moved to another community
select fx_event(:'existingEventID', :'groupID', :'eventCategory1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when event category is from same community as group
select lives_ok(
    format('insert into event (event_id, group_id, name, slug, description, timezone, event_category_id, event_kind_id) values (%L, %L, %L, %L, %L, %L, %L, %L)',
        :'eventID', :'groupID', 'Test Event', 'test-event', 'A test event', 'UTC', :'eventCategory1ID', 'in-person'),
    'Should succeed when event category is from same community as group'
);

-- Should fail when event category is from different community
select throws_ok(
    format('insert into event (event_id, group_id, name, slug, description, timezone, event_category_id, event_kind_id) values (%L, %L, %L, %L, %L, %L, %L, %L)',
        :'crossCommunityEventID', :'groupID', 'Another Event', 'another-event', 'Another test event', 'UTC', :'eventCategory2ID', 'in-person'),
    'OCG01',
    'event category not found in community',
    'Should fail when event category is from different community'
);

-- Should fail when updating event to category from different community
select throws_ok(
    format('update event set event_category_id = %L where event_id = %L', :'eventCategory2ID', :'existingEventID'),
    'OCG01',
    'event category not found in community',
    'Should fail when updating event to category from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
