-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '4a0c0000-0000-0000-0000-000000000001'
\set eventAID '4a0c0000-0000-0000-0000-000000000002'
\set eventBID '4a0c0000-0000-0000-0000-000000000003'
\set eventCanceledID '4a0c0000-0000-0000-0000-000000000004'
\set eventCategoryID '4a0c0000-0000-0000-0000-000000000005'
\set eventCID '4a0c0000-0000-0000-0000-000000000006'
\set eventDeletedGroupID '4a0c0000-0000-0000-0000-000000000007'
\set eventDeletedID '4a0c0000-0000-0000-0000-000000000008'
\set eventInactiveGroupID '4a0c0000-0000-0000-0000-000000000009'
\set eventNoStartsAtID '4a0c0000-0000-0000-0000-000000000010'
\set eventPaidID '4a0c0000-0000-0000-0000-000000000011'
\set eventPaidPriceWindowID '4a0c0000-0000-0000-0000-000000000012'
\set eventPaidPurchaseID '4a0c0000-0000-0000-0000-000000000013'
\set eventPaidTicketTypeID '4a0c0000-0000-0000-0000-000000000014'
\set eventPastID '4a0c0000-0000-0000-0000-000000000015'
\set eventPendingInvitationID '4a0c0000-0000-0000-0000-000000000016'
\set eventQuestionsID '4a0c0000-0000-0000-0000-000000000017'
\set eventQuestionsTicketTypeID '4a0c0000-0000-0000-0000-000000000018'
\set eventUnpublishedID '4a0c0000-0000-0000-0000-000000000019'
\set groupCategoryID '4a0c0000-0000-0000-0000-000000000020'
\set groupDeletedID '4a0c0000-0000-0000-0000-000000000021'
\set groupID '4a0c0000-0000-0000-0000-000000000022'
\set groupInactiveID '4a0c0000-0000-0000-0000-000000000023'
\set questionsAttendeeUserID '4a0c0000-0000-0000-0000-000000000024'
\set questionsCheckoutExpiredPurchaseID '4a0c0000-0000-0000-0000-000000000025'
\set questionsCheckoutExpiredUserID '4a0c0000-0000-0000-0000-000000000026'
\set questionsCheckoutPurchaseID '4a0c0000-0000-0000-0000-000000000027'
\set questionsCheckoutUserID '4a0c0000-0000-0000-0000-000000000028'
\set questionsInvitedUserID '4a0c0000-0000-0000-0000-000000000029'
\set registrationQuestionID '4a0c0000-0000-0000-0000-000000000030'
\set sessionAID '4a0c0000-0000-0000-0000-000000000031'
\set sessionCID '4a0c0000-0000-0000-0000-000000000032'
\set userEmptyID '4a0c0000-0000-0000-0000-000000000033'
\set userID '4a0c0000-0000-0000-0000-000000000034'
\set userPaidID '4a0c0000-0000-0000-0000-000000000035'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'alliance-one',
    'Alliance One',
    'Alliance for testing user event listings',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Meetup');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'userID',
    'auth-hash',
    'alice@example.com',
    true,
    'alice',
    'Alice'
), (
    :'userPaidID',
    'paid-auth-hash',
    'paid@example.com',
    true,
    'paid',
    'Paid User'
), (
    :'questionsAttendeeUserID',
    'attendee-auth-hash',
    'rq-attendee@test.com',
    true,
    'rq-attendee',
    'RQ Attendee'
), (
    :'questionsCheckoutUserID',
    'checkout-auth-hash',
    'rq-checkout@test.com',
    true,
    'rq-checkout',
    'RQ Checkout'
), (
    :'questionsCheckoutExpiredUserID',
    'expired-auth-hash',
    'rq-expired@test.com',
    true,
    'rq-expired',
    'RQ Expired'
), (
    :'questionsInvitedUserID',
    'invited-auth-hash',
    'rq-invited@test.com',
    true,
    'rq-invited',
    'RQ Invited'
);

-- Groups
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values (
    :'groupDeletedID',
    :'allianceID',
    :'groupCategoryID',
    'Deleted Group',
    'deleted-group',
    false,
    true
), (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Main Group',
    'main-group',
    true,
    false
), (
    :'groupInactiveID',
    :'allianceID',
    :'groupCategoryID',
    'Inactive Group',
    'inactive-group',
    false,
    false
);

-- Events
insert into event (
    event_id,
    canceled,
    deleted,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    timezone
) values
    (
        :'eventAID',
        false,
        false,
        'Event A',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Event A',
        null,
        true,
        'event-a',
        '2099-01-10 10:00:00+00',
        'UTC'
    ),
    (
        :'eventBID',
        false,
        false,
        'Event B',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event B',
        null,
        true,
        'event-b',
        '2099-01-11 10:00:00+00',
        'UTC'
    ),
    (
        :'eventCanceledID',
        true,
        false,
        'Event Canceled',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event Canceled',
        null,
        false,
        'event-canceled',
        '2099-01-13 10:00:00+00',
        'UTC'
    ),
    (
        :'eventCID',
        false,
        false,
        'Event C',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event C',
        null,
        true,
        'event-c',
        '2099-01-12 10:00:00+00',
        'UTC'
    ),
    (
        :'eventDeletedID',
        false,
        true,
        'Event Deleted',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event Deleted',
        null,
        false,
        'event-deleted',
        '2099-01-14 10:00:00+00',
        'UTC'
    ),
    (
        :'eventInactiveGroupID',
        false,
        false,
        'Event Inactive Group',
        :'eventCategoryID',
        'virtual',
        :'groupInactiveID',
        'Event Inactive Group',
        null,
        true,
        'event-inactive-group',
        '2099-01-15 10:00:00+00',
        'UTC'
    ),
    (
        :'eventNoStartsAtID',
        false,
        false,
        'Event No Start',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event No Start',
        null,
        false,
        'event-no-start',
        null,
        'UTC'
    ),
    (
        :'eventPastID',
        false,
        false,
        'Event Past',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event Past',
        null,
        true,
        'event-past',
        '2000-01-01 10:00:00+00',
        'UTC'
    ),
    (
        :'eventPendingInvitationID',
        false,
        false,
        'Event Pending Invitation',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event Pending Invitation',
        null,
        true,
        'event-pending-invitation',
        '2099-01-13 12:00:00+00',
        'UTC'
    ),
    (
        :'eventUnpublishedID',
        false,
        false,
        'Event Unpublished',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event Unpublished',
        null,
        false,
        'event-unpublished',
        '2099-01-16 10:00:00+00',
        'UTC'
    ),
    (
        :'eventDeletedGroupID',
        false,
        false,
        'Event Deleted Group',
        :'eventCategoryID',
        'virtual',
        :'groupDeletedID',
        'Event Deleted Group',
        null,
        true,
        'event-deleted-group',
        '2099-01-17 10:00:00+00',
        'UTC'
    ),
    (
        :'eventPaidID',
        false,
        false,
        'Event Paid',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Event Paid',
        'USD',
        true,
        'event-paid',
        '2099-01-18 10:00:00+00',
        'UTC'
    );

-- Event with registration questions shown in user event lists
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    published,
    registration_questions,
    starts_at,
    timezone
) values (
    :'eventQuestionsID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Questions Event',
    'questions-event',
    'Event with registration questions',
    true,
    format(
        $json$
            [
                {
                    "id": "%s",
                    "kind": "free-text",
                    "prompt": "Note",
                    "required": true,
                    "options": []
                }
            ]
        $json$,
        :'registrationQuestionID'
    )::jsonb,
    now() + interval '1 day',
    'UTC'
);

-- Sessions for speaker role tests
insert into session (session_id, event_id, name, session_kind_id, starts_at) values
    (:'sessionAID', :'eventAID', 'Session A', 'virtual', '2099-01-10 11:00:00+00'),
    (:'sessionCID', :'eventCID', 'Session C', 'virtual', '2099-01-12 11:00:00+00');

-- Event ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'eventPaidTicketTypeID',
    :'eventPaidID',
    1,
    1,
    'Paid admission'
), (
    :'eventQuestionsTicketTypeID',
    :'eventQuestionsID',
    1,
    100,
    'Questions admission'
);

-- Paid ticket price window used by purchase state tests
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'eventPaidPriceWindowID',
    1500,
    :'eventPaidTicketTypeID'
);

-- User participation
insert into event_attendee (event_id, user_id, status) values
    (:'eventAID', :'userID', 'confirmed'),
    (:'eventBID', :'userID', 'confirmed'),
    (:'eventCanceledID', :'userID', 'confirmed'),
    (:'eventDeletedGroupID', :'userID', 'confirmed'),
    (:'eventDeletedID', :'userID', 'confirmed'),
    (:'eventInactiveGroupID', :'userID', 'confirmed'),
    (:'eventNoStartsAtID', :'userID', 'confirmed'),
    (:'eventPastID', :'userID', 'confirmed'),
    (:'eventPaidID', :'userPaidID', 'confirmed'),
    (:'eventPendingInvitationID', :'userID', 'invitation-pending'),
    (:'eventUnpublishedID', :'userID', 'confirmed');

-- User event rows for registration-question states
insert into event_attendee (event_id, user_id, manually_invited, status, registration_answers)
values
    (:'eventQuestionsID', :'questionsInvitedUserID', true, 'registration-questions-pending', null),
    (
        :'eventQuestionsID',
        :'questionsCheckoutUserID',
        false,
        'registration-questions-pending',
        format(
            '{"answers": [{"question_id": "%s", "value": "Checkout answer"}]}',
            :'registrationQuestionID'
        )::jsonb
    ),
    (
        :'eventQuestionsID',
        :'questionsCheckoutExpiredUserID',
        false,
        'registration-questions-pending',
        format(
            '{"answers": [{"question_id": "%s", "value": "Expired answer"}]}',
            :'registrationQuestionID'
        )::jsonb
    ),
    (
        :'eventQuestionsID',
        :'questionsAttendeeUserID',
        false,
        'confirmed',
        format(
            '{"answers": [{"question_id": "%s", "value": "Attendee answer"}]}',
            :'registrationQuestionID'
        )::jsonb
    );

-- User roles for role aggregation
insert into event_host (event_id, user_id) values
    (:'eventAID', :'userID');

insert into event_speaker (event_id, user_id, featured) values
    (:'eventAID', :'userID', true);

insert into session_speaker (session_id, user_id, featured) values
    (:'sessionAID', :'userID', false),
    (:'sessionCID', :'userID', true);

-- Completed paid purchase used to disable attendee cancellation
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'eventPaidPurchaseID',
    1500,
    'USD',
    :'eventPaidID',
    :'eventPaidTicketTypeID',
    'completed',
    'Paid admission',
    :'userPaidID'
);

-- Pending checkout purchases used to distinguish active and expired holds
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    provider_checkout_url,
    status,
    ticket_title,
    user_id
) values (
    :'questionsCheckoutPurchaseID',
    1500,
    'USD',
    :'eventQuestionsID',
    :'eventQuestionsTicketTypeID',
    current_timestamp + interval '10 minutes',
    'https://example.test/checkout/resume',
    'pending',
    'Questions admission',
    :'questionsCheckoutUserID'
), (
    :'questionsCheckoutExpiredPurchaseID',
    1500,
    'USD',
    :'eventQuestionsID',
    :'eventQuestionsTicketTypeID',
    current_timestamp - interval '10 minutes',
    'https://example.test/checkout/expired',
    'pending',
    'Questions admission',
    :'questionsCheckoutExpiredUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list only valid upcoming events sorted by date asc
select is(
    list_user_events(:'userID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        jsonb_build_array(
            jsonb_build_object(
                'attendance_status',
                'attendee',
                'event',
                get_event_summary(:'allianceID'::uuid, :'groupID'::uuid, :'eventAID'::uuid)::jsonb,
                'has_paid_purchase',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'allianceID'::uuid, :'eventAID'::uuid)::jsonb,
                'resume_checkout_url',
                null,
                'roles',
                jsonb_build_array('attendee', 'host', 'speaker')
            ),
            jsonb_build_object(
                'attendance_status',
                'attendee',
                'event',
                get_event_summary(:'allianceID'::uuid, :'groupID'::uuid, :'eventBID'::uuid)::jsonb,
                'has_paid_purchase',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'allianceID'::uuid, :'eventBID'::uuid)::jsonb,
                'resume_checkout_url',
                null,
                'roles',
                jsonb_build_array('attendee')
            ),
            jsonb_build_object(
                'attendance_status',
                null,
                'event',
                get_event_summary(:'allianceID'::uuid, :'groupID'::uuid, :'eventCID'::uuid)::jsonb,
                'has_paid_purchase',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'allianceID'::uuid, :'eventCID'::uuid)::jsonb,
                'resume_checkout_url',
                null,
                'roles',
                jsonb_build_array('speaker')
            )
        ),
        'total',
        3
    ),
    'Should list only valid upcoming events sorted by date asc'
);

-- Should deduplicate roles per event
select is(
    (
        list_user_events(:'userID'::uuid, '{"limit": 1, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
        -> 'roles'
    ),
    jsonb_build_array('attendee', 'host', 'speaker'),
    'Should deduplicate roles per event'
);

-- Should paginate events and keep total count
select is(
    list_user_events(:'userID'::uuid, '{"limit": 1, "offset": 1}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        jsonb_build_array(
            jsonb_build_object(
                'attendance_status',
                'attendee',
                'event',
                get_event_summary(:'allianceID'::uuid, :'groupID'::uuid, :'eventBID'::uuid)::jsonb,
                'has_paid_purchase',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'allianceID'::uuid, :'eventBID'::uuid)::jsonb,
                'resume_checkout_url',
                null,
                'roles',
                jsonb_build_array('attendee')
            )
        ),
        'total',
        3
    ),
    'Should paginate events and keep total count'
);

-- Should not allow paid attendee-only events to be canceled from My Events
select is(
    list_user_events(:'userPaidID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        jsonb_build_array(
            jsonb_build_object(
                'attendance_status',
                'attendee',
                'event',
                get_event_summary(:'allianceID'::uuid, :'groupID'::uuid, :'eventPaidID'::uuid)::jsonb,
                'has_paid_purchase',
                true,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'allianceID'::uuid, :'eventPaidID'::uuid)::jsonb,
                'resume_checkout_url',
                null,
                'roles',
                jsonb_build_array('attendee')
            )
        ),
        'total',
        1
    ),
    'Should not allow paid attendee-only events to be canceled from My Events'
);

-- Should return empty result for users without events
select is(
    list_user_events(:'userEmptyID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        '[]'::jsonb,
        'total',
        0
    ),
    'Should return empty result for users without events'
);

-- Should include manually invited pending registration events in the user dashboard
select is(
    (
        list_user_events(:'questionsInvitedUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
    ) - 'event',
    jsonb_build_object(
        'attendance_status',
        'registration-questions-pending',
        'has_paid_purchase',
        false,
        'manually_invited',
        true,
        'registration_answers',
        null,
        'registration_questions',
        get_event_registration_questions(:'communityID'::uuid, :'eventQuestionsID'::uuid)::jsonb,
        'resume_checkout_url',
        null,
        'roles',
        jsonb_build_array('attendee')
    ),
    'Should include manually invited pending registration events in the user dashboard'
);

-- Should return registration questions for pending users
select is(
    jsonb_array_length(
        list_user_events(:'questionsInvitedUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
        -> 'registration_questions'
    )::text,
    '1',
    'Should return registration questions for pending users'
);

-- Should return registration questions and answers for confirmed attendees
select is(
    (
        list_user_events(:'questionsAttendeeUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
    ) - 'event',
    jsonb_build_object(
        'attendance_status',
        'attendee',
        'has_paid_purchase',
        false,
        'registration_answers',
        format(
            '{"answers": [{"question_id": "%s", "value": "Attendee answer"}]}',
            :'registrationQuestionID'
        )::jsonb,
        'registration_questions',
        get_event_registration_questions(:'communityID'::uuid, :'eventQuestionsID'::uuid)::jsonb,
        'resume_checkout_url',
        null,
        'roles',
        jsonb_build_array('attendee')
    ),
    'Should return registration questions and answers for confirmed attendees'
);

-- Should report active pending checkout before pending registration questions
select is(
    (
        list_user_events(:'questionsCheckoutUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
    ) - 'event',
    jsonb_build_object(
        'attendance_status',
        'pending-payment',
        'has_paid_purchase',
        false,
        'registration_answers',
        format(
            '{"answers": [{"question_id": "%s", "value": "Checkout answer"}]}',
            :'registrationQuestionID'
        )::jsonb,
        'registration_questions',
        get_event_registration_questions(:'communityID'::uuid, :'eventQuestionsID'::uuid)::jsonb,
        'resume_checkout_url',
        'https://example.test/checkout/resume',
        'roles',
        jsonb_build_array('attendee')
    ),
    'Should report active pending checkout before pending registration questions'
);

-- Should ignore expired pending checkout before pending registration questions
select is(
    (
        list_user_events(:'questionsCheckoutExpiredUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
    ) - 'event',
    jsonb_build_object(
        'attendance_status',
        'registration-questions-pending',
        'has_paid_purchase',
        false,
        'registration_answers',
        format(
            '{"answers": [{"question_id": "%s", "value": "Expired answer"}]}',
            :'registrationQuestionID'
        )::jsonb,
        'registration_questions',
        get_event_registration_questions(:'communityID'::uuid, :'eventQuestionsID'::uuid)::jsonb,
        'resume_checkout_url',
        null,
        'roles',
        jsonb_build_array('attendee')
    ),
    'Should ignore expired pending checkout before pending registration questions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
