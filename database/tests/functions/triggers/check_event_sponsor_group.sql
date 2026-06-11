-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab030000-0000-0000-0000-000000000001'
\set eventCategoryID 'ab030000-0000-0000-0000-000000000002'
\set eventID 'ab030000-0000-0000-0000-000000000003'
\set group1CategoryID 'ab030000-0000-0000-0000-000000000004'
\set group1ID 'ab030000-0000-0000-0000-000000000005'
\set group2CategoryID 'ab030000-0000-0000-0000-000000000006'
\set group2ID 'ab030000-0000-0000-0000-000000000007'
\set sponsor1ID 'ab030000-0000-0000-0000-000000000008'
\set sponsor2ID 'ab030000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event Category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Conference');

-- Group Categories
insert into group_category (group_category_id, community_id, name) values
    (:'group1CategoryID', :'communityID', 'Technology'),
    (:'group2CategoryID', :'communityID', 'Science');

-- Group 1
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'group1ID',
    :'communityID',
    :'group1CategoryID',
    'Test Group 1',
    'test-group-1',
    'A test group 1'
);

-- Group 2
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'group2ID',
    :'communityID',
    :'group2CategoryID',
    'Test Group 2',
    'test-group-2',
    'A test group 2'
);

-- Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url) values
    (:'sponsor1ID', :'group1ID', 'Sponsor 1', 'https://example.com/sponsor1.png'),
    (:'sponsor2ID', :'group2ID', 'Sponsor 2', 'https://example.com/sponsor2.png');

-- Event (belongs to group 1)
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'group1ID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC'
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
