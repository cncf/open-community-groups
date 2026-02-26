-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventID '00000000-0000-0000-0000-000000000101'
\set group1CategoryID '00000000-0000-0000-0000-000000000010'
\set group1ID '00000000-0000-0000-0000-000000000051'
\set group2CategoryID '00000000-0000-0000-0000-000000000012'
\set group2ID '00000000-0000-0000-0000-000000000052'
\set sponsor1ID '00000000-0000-0000-0000-000000000061'
\set sponsor2ID '00000000-0000-0000-0000-000000000062'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'categoryID', 'Conference', :'communityID');

-- Group Categories
insert into group_category (group_category_id, name, community_id) values
    (:'group1CategoryID', 'Technology', :'communityID'),
    (:'group2CategoryID', 'Science', :'communityID');

-- Group 1
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'group1ID',
    :'communityID',
    'Test Group 1',
    'test-group-1',
    'A test group 1',
    :'group1CategoryID'
);

-- Group 2
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'group2ID',
    :'communityID',
    'Test Group 2',
    'test-group-2',
    'A test group 2',
    :'group2CategoryID'
);

-- Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url) values
    (:'sponsor1ID', :'group1ID', 'Sponsor 1', 'https://example.com/sponsor1.png'),
    (:'sponsor2ID', :'group2ID', 'Sponsor 2', 'https://example.com/sponsor2.png');

-- Event (belongs to group 1)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'eventID',
    :'group1ID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC',
    :'categoryID',
    'in-person'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when sponsor is from same group as event
select lives_ok(
    format('insert into event_sponsor (event_id, group_sponsor_id, level) values (%L, %L, ''Gold'')', :'eventID', :'sponsor1ID'),
    'Should succeed when sponsor is from same group as event'
);

-- Should fail when sponsor is from different group
select throws_ok(
    format('insert into event_sponsor (event_id, group_sponsor_id, level) values (%L, %L, ''Gold'')', :'eventID', :'sponsor2ID'),
    'sponsor not found in group',
    'Should fail when sponsor is from different group'
);

-- Should fail when updating event_sponsor to sponsor from different group
select throws_ok(
    format('update event_sponsor set group_sponsor_id = %L where event_id = %L', :'sponsor2ID', :'eventID'),
    'sponsor not found in group',
    'Should fail when updating event_sponsor to sponsor from different group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
