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
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'Active Group', 'active-group');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'user1ID', 'h', 'u1@test.com', 'u1'),
    (:'user2ID', 'h', 'u2@test.com', 'u2');

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    waitlist_enabled
)
values
    (:'event1ID', :'groupID', 'Event 1', 'event-1', 'd', 'UTC', :'eventCategoryID', 'in-person', 1, true, true),
    (:'event2ID', :'groupID', 'Event 2', 'event-2', 'd', 'UTC', :'eventCategoryID', 'in-person', 1, true, true);

-- Existing attendees
insert into event_attendee (event_id, user_id)
values
    (:'event1ID', :'user1ID'),
    (:'event2ID', :'user1ID');

-- Existing waitlist entry
insert into event_waitlist (event_id, user_id)
values (:'event2ID', :'user2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow waitlist inserts when the user is not already attending
select lives_ok(
    format(
        'insert into event_waitlist (event_id, user_id) values (%L, %L)',
        :'event1ID',
        :'user2ID'
    ),
    'Should allow waitlist inserts when the user is not already attending'
);

-- Should reject waitlist inserts when the user is already attending
select throws_ok(
    format(
        'insert into event_waitlist (event_id, user_id) values (%L, %L)',
        :'event1ID',
        :'user1ID'
    ),
    'user is already attending this event',
    'Should reject waitlist inserts when the user is already attending'
);

-- Should reject waitlist updates that move a user onto an attendee pair
select throws_ok(
    format(
        'update event_waitlist set user_id = %L where event_id = %L and user_id = %L',
        :'user1ID',
        :'event2ID',
        :'user2ID'
    ),
    'user is already attending this event',
    'Should reject waitlist updates that target an attendee pair'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
