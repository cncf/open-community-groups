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
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set eventID '00000000-0000-0000-0000-000000000101'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000051'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community 1
insert into community (community_id, name, display_name, description, logo_url)
values (:'community1ID', 'community-1', 'Community 1', 'Test community 1', 'https://example.com/logo.png');

-- Community 2
insert into community (community_id, name, display_name, description, logo_url)
values (:'community2ID', 'community-2', 'Community 2', 'Test community 2', 'https://example.com/logo.png');

-- Event Category 1 (belongs to community 1)
insert into event_category (event_category_id, name, slug, community_id)
values (:'category1ID', 'Conference', 'conference', :'community1ID');

-- Event Category 2 (belongs to community 2)
insert into event_category (event_category_id, name, slug, community_id)
values (:'category2ID', 'Workshop', 'workshop', :'community2ID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'community1ID');

-- Group (belongs to community 1)
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'community1ID',
    'Test Group',
    'test-group',
    'A test group',
    :'groupCategoryID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when event category is from same community as group
select lives_ok(
    format('insert into event (event_id, group_id, name, slug, description, timezone, event_category_id, event_kind_id) values (%L, %L, %L, %L, %L, %L, %L, %L)',
        :'eventID', :'groupID', 'Test Event', 'test-event', 'A test event', 'UTC', :'category1ID', 'in-person'),
    'Should succeed when event category is from same community as group'
);

-- Should fail when event category is from different community
select throws_ok(
    format('insert into event (event_id, group_id, name, slug, description, timezone, event_category_id, event_kind_id) values (%L, %L, %L, %L, %L, %L, %L, %L)',
        gen_random_uuid(), :'groupID', 'Another Event', 'another-event', 'Another test event', 'UTC', :'category2ID', 'in-person'),
    'event category not found in community',
    'Should fail when event category is from different community'
);

-- Should fail when updating event to category from different community
select throws_ok(
    format('update event set event_category_id = %L where event_id = %L', :'category2ID', :'eventID'),
    'event category not found in community',
    'Should fail when updating event to category from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
