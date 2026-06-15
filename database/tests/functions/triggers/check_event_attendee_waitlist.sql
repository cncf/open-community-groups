-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab010000-0000-0000-0000-000000000001'
\set event1ID 'ab010000-0000-0000-0000-000000000002'
\set event2ID 'ab010000-0000-0000-0000-000000000003'
\set eventCategoryID 'ab010000-0000-0000-0000-000000000004'
\set groupCategoryID 'ab010000-0000-0000-0000-000000000005'
\set groupID 'ab010000-0000-0000-0000-000000000006'
\set user1ID 'ab010000-0000-0000-0000-000000000007'
\set user2ID 'ab010000-0000-0000-0000-000000000008'

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

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Active Group', 'active-group');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'user1ID', 'user-one-hash', 'user-one@example.com', true, 'user-one'),
    (:'user2ID', 'user-two-hash', 'user-two@example.com', true, 'user-two');

-- Events
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    capacity,
    published,
    timezone,
    waitlist_enabled
)
values
    (
        :'event1ID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Event 1',
        'event-1',
        'First waitlist test event',
        1,
        true,
        'UTC',
        true
    ),
    (
        :'event2ID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Event 2',
        'event-2',
        'Second waitlist test event',
        1,
        true,
        'UTC',
        true
    );

-- Existing waitlist entries
insert into event_waitlist (event_id, user_id)
values
    (:'event1ID', :'user1ID'),
    (:'event2ID', :'user1ID');

-- Existing attendee
insert into event_attendee (event_id, user_id)
values (:'event2ID', :'user2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow attendee inserts when the user is not on the waitlist
select lives_ok(
    format(
        'insert into event_attendee (event_id, user_id) values (%L, %L)',
        :'event1ID',
        :'user2ID'
    ),
    'Should allow attendee inserts when the user is not on the waitlist'
);

-- Should reject attendee inserts when the user is already on the waitlist
select throws_ok(
    format(
        'insert into event_attendee (event_id, user_id) values (%L, %L)',
        :'event1ID',
        :'user1ID'
    ),
    'user is already on the waiting list for this event',
    'Should reject attendee inserts when the user is already waitlisted'
);

-- Should reject attendee updates that move a user onto a waitlisted pair
select throws_ok(
    format(
        'update event_attendee set user_id = %L where event_id = %L and user_id = %L',
        :'user1ID',
        :'event2ID',
        :'user2ID'
    ),
    'user is already on the waiting list for this event',
    'Should reject attendee updates that target a waitlisted pair'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
