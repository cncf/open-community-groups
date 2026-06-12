-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a410000-0000-0000-0000-000000000001'
\set eventCategoryID '3a410000-0000-0000-0000-000000000002'
\set eventID '3a410000-0000-0000-0000-000000000003'
\set eventManualOverCapacityID '3a410000-0000-0000-0000-000000000004'
\set eventQuestionsID '3a410000-0000-0000-0000-000000000005'
\set groupCategoryID '3a410000-0000-0000-0000-000000000006'
\set groupID '3a410000-0000-0000-0000-000000000007'
\set questionsSeatedUserID '3a410000-0000-0000-0000-000000000008'
\set questionsWaitlistUserID '3a410000-0000-0000-0000-000000000009'
\set user1ID '3a410000-0000-0000-0000-000000000010'
\set user2ID '3a410000-0000-0000-0000-000000000011'
\set user3ID '3a410000-0000-0000-0000-000000000012'
\set user4ID '3a410000-0000-0000-0000-000000000013'
\set user5ID '3a410000-0000-0000-0000-000000000014'

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
    'capacity-community',
    'Capacity Community',
    'A test community for event capacity',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Capacity Group', 'capacity-group');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'user1ID', gen_random_bytes(32), 'user1@example.com', 'user1', true, 'User 1'),
    (:'user2ID', gen_random_bytes(32), 'user2@example.com', 'user2', true, 'User 2'),
    (:'user3ID', gen_random_bytes(32), 'user3@example.com', 'user3', true, 'User 3'),
    (:'user4ID', gen_random_bytes(32), 'user4@example.com', 'user4', true, 'User 4'),
    (:'user5ID', gen_random_bytes(32), 'user5@example.com', 'user5', true, 'User 5'),
    (
        :'questionsSeatedUserID',
        gen_random_bytes(32),
        'rq-seated@example.com',
        'rq-seated',
        true,
        'RQ Seated'
    ),
    (
        :'questionsWaitlistUserID',
        gen_random_bytes(32),
        'rq-waitlist@example.com',
        'rq-waitlist',
        true,
        'RQ Waitlist'
    );

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

-- Event with pending registration-question attendee used for capacity counting
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
    starts_at
) values (
    :'eventQuestionsID',
    :'groupID',
    'Waitlist Questions Event',
    'waitlist-questions-event',
    'd',
    'UTC',
    :'eventCategoryID',
    'virtual',
    2,
    '2030-01-03 10:00:00+00'
);

-- Event over capacity because of a confirmed manual invitation
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
    starts_at
) values (
    :'eventManualOverCapacityID',
    :'groupID',
    'Manual Over Capacity Event',
    'manual-over-capacity-event',
    'Event used for manual invitation capacity validation tests',
    'UTC',
    :'eventCategoryID',
    'virtual',
    2,
    '2030-01-04 10:00:00+00'
);

-- Event attendees
insert into event_attendee (event_id, user_id, status) values
    (:'eventID', :'user1ID', 'confirmed'),
    (:'eventID', :'user2ID', 'confirmed'),
    (:'eventID', :'user3ID', 'confirmed'),
    (:'eventID', :'user4ID', 'invitation-pending'),
    (:'eventID', :'user5ID', 'invitation-rejected'),
    (:'eventQuestionsID', :'questionsSeatedUserID', 'confirmed'),
    (:'eventQuestionsID', :'questionsWaitlistUserID', 'registration-questions-pending');

-- Over-capacity event attendees with one organizer-controlled manual seat
insert into event_attendee (event_id, user_id, manually_invited, status) values
    (:'eventManualOverCapacityID', :'user1ID', false, 'confirmed'),
    (:'eventManualOverCapacityID', :'user2ID', false, 'confirmed'),
    (:'eventManualOverCapacityID', :'user3ID', true, 'confirmed'),
    (:'eventManualOverCapacityID', :'user4ID', true, 'invitation-pending');

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

-- Should validate provider limits against the effective capacity override
select throws_ok(
    $$select validate_event_capacity(
        '{"capacity": 10, "meeting_requested": true, "meeting_provider_id": "zoom"}'::jsonb,
        '{"zoom": 100}'::jsonb,
        null,
        200
    )$$,
    'event capacity (200) exceeds maximum participants allowed (100)',
    'Should validate provider limits against the effective capacity override'
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

-- Should count pending registration rows as attendees during capacity validation
select throws_ok(
    format(
        $$select validate_event_capacity('{"capacity": 0}'::jsonb, null::jsonb, '%s'::uuid)$$,
        :'eventQuestionsID'
    ),
    'event capacity (0) cannot be less than current number of attendees (2)',
    'Should count pending registration rows as attendees during capacity validation'
);

-- Should allow manual invitation seats above event capacity
select lives_ok(
    format(
        $$select validate_event_capacity('{"capacity": 2}'::jsonb, null::jsonb, '%s'::uuid)$$,
        :'eventManualOverCapacityID'
    ),
    'Should allow manual invitation seats above event capacity'
);

-- Should reject capacity below non-manual occupied seats
select throws_ok(
    format(
        $$select validate_event_capacity('{"capacity": 1}'::jsonb, null::jsonb, '%s'::uuid)$$,
        :'eventManualOverCapacityID'
    ),
    'event capacity (1) cannot be less than current number of attendees (3)',
    'Should reject capacity below non-manual occupied seats'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
