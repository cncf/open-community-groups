-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000021'
\set groupCategoryID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000041'
\set user1ID '00000000-0000-0000-0000-000000000051'
\set user2ID '00000000-0000-0000-0000-000000000052'
\set user3ID '00000000-0000-0000-0000-000000000053'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'community-1', 'Community 1', 'Test community', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Group 1', 'group-1');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'user1ID', gen_random_bytes(32), 'user1@example.com', 'user1', true, 'User 1'),
    (:'user2ID', gen_random_bytes(32), 'user2@example.com', 'user2', true, 'User 2'),
    (:'user3ID', gen_random_bytes(32), 'user3@example.com', 'user3', true, 'User 3');

-- Event
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
    starts_at,
    ends_at
) values (
    :'eventID',
    :'groupID',
    'Capacity Test Event',
    'capacity-test-event',
    'Event used for capacity validation tests',
    'UTC',
    :'eventCategoryID',
    'virtual',
    10,
    '2030-01-01 10:00:00+00',
    '2030-01-01 11:00:00+00'
);

-- Event attendees
insert into event_attendee (event_id, user_id) values
    (:'eventID', :'user1ID'),
    (:'eventID', :'user2ID'),
    (:'eventID', :'user3ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject capacity above the meeting provider limit
select throws_ok(
    $$select validate_event_capacity(
        '{"capacity": 200, "meeting_requested": true, "meeting_provider_id": "zoom"}'::jsonb,
        '{"zoom": 100}'::jsonb
    )$$,
    'event capacity (200) exceeds maximum participants allowed (100)',
    'Should reject capacity above the meeting provider limit'
);

-- Should accept capacity within the meeting provider limit
select lives_ok(
    $$select validate_event_capacity(
        '{"capacity": 100, "meeting_requested": true, "meeting_provider_id": "zoom"}'::jsonb,
        '{"zoom": 100}'::jsonb
    )$$,
    'Should accept capacity within the meeting provider limit'
);

-- Should ignore provider limits when no meeting is requested
select lives_ok(
    $$select validate_event_capacity(
        '{"capacity": 200, "meeting_requested": false}'::jsonb,
        '{"zoom": 100}'::jsonb
    )$$,
    'Should ignore provider limits when no meeting is requested'
);

-- Should reject update capacity below the current attendee count
select throws_ok(
    format(
        $$select validate_event_capacity(
            '{"capacity": 2}'::jsonb,
            null,
            '%s'::uuid
        )$$,
        :'eventID'
    ),
    'event capacity (2) cannot be less than current number of attendees (3)',
    'Should reject update capacity below the current attendee count'
);

-- Should accept update capacity equal to the current attendee count
select lives_ok(
    format(
        $$select validate_event_capacity(
            '{"capacity": 3}'::jsonb,
            null,
            '%s'::uuid
        )$$,
        :'eventID'
    ),
    'Should accept update capacity equal to the current attendee count'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
