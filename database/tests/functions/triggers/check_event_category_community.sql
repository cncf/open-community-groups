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
\set eventCategory1ID 'ab020000-0000-0000-0000-000000000003'
\set eventCategory2ID 'ab020000-0000-0000-0000-000000000004'
\set eventID 'ab020000-0000-0000-0000-000000000005'
\set groupCategoryID 'ab020000-0000-0000-0000-000000000006'
\set groupID 'ab020000-0000-0000-0000-000000000007'
\set missingEventID 'ab020000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories and groups
select fx_community(:'community1ID');
select fx_community(:'community2ID');
select fx_group_category(:'groupCategoryID', :'community1ID');
select fx_group(:'groupID', :'community1ID', :'groupCategoryID');

-- Event Category 1 (belongs to community 1)
insert into event_category (event_category_id, community_id, name)
values (:'eventCategory1ID', :'community1ID', 'Conference');

-- Event Category 2 (belongs to community 2)
insert into event_category (event_category_id, community_id, name)
values (:'eventCategory2ID', :'community2ID', 'Workshop');

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
        :'missingEventID', :'groupID', 'Another Event', 'another-event', 'Another test event', 'UTC', :'eventCategory2ID', 'in-person'),
    'OCG01',
    'event category not found in community',
    'Should fail when event category is from different community'
);

-- Should fail when updating event to category from different community
select throws_ok(
    format('update event set event_category_id = %L where event_id = %L', :'eventCategory2ID', :'eventID'),
    'OCG01',
    'event category not found in community',
    'Should fail when updating event to category from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
