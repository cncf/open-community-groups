-- Tests validating event capacity changes.

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

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'questionsSeatedUserID');
select fx_user(:'questionsWaitlistUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID', jsonb_build_object('username', 'user1-validate-event-capacity'));
select fx_user(:'user2ID', jsonb_build_object('username', 'user2-validate-event-capacity'));
select fx_user(:'user3ID', jsonb_build_object('username', 'user3-validate-event-capacity'));
select fx_user(:'user4ID', jsonb_build_object('username', 'user4-validate-event-capacity'));
select fx_user(:'user5ID', jsonb_build_object('username', 'user5-validate-event-capacity'));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 10,
    'ends_at', '2030-01-01 11:00:00+00',
    'event_kind_id', 'virtual',
    'starts_at', '2030-01-01 10:00:00+00'
));

-- Event with pending registration-question attendee used for capacity counting
select fx_event(:'eventQuestionsID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 2,
    'description', 'd',
    'event_kind_id', 'virtual',
    'starts_at', '2030-01-03 10:00:00+00'
));

-- Event over capacity because of a confirmed manual invitation
select fx_event(:'eventManualOverCapacityID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 2,
    'event_kind_id', 'virtual',
    'starts_at', '2030-01-04 10:00:00+00'
));

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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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

-- Should exclude pending registration rows without an active checkout hold
select throws_ok(
    format(
        $$select validate_event_capacity('{"capacity": 0}'::jsonb, null::jsonb, '%s'::uuid)$$,
        :'eventQuestionsID'
    ),
    'OCG01',
    'event capacity (0) cannot be less than current number of attendees (1)',
    'Should exclude pending registration rows without an active checkout hold'
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
    'OCG01',
    'event capacity (1) cannot be less than current number of attendees (3)',
    'Should reject capacity below non-manual occupied seats'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
