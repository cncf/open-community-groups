-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupDeletedID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000032'
\set groupInactiveID '00000000-0000-0000-0000-000000000033'
\set questionsAttendeeUserID '90400000-0000-0000-0000-000000000031'
\set questionsCheckoutExpiredPurchaseID '90400000-0000-0000-0000-000000000063'
\set questionsCheckoutExpiredUserID '90400000-0000-0000-0000-000000000035'
\set questionsCheckoutPurchaseID '90400000-0000-0000-0000-000000000062'
\set questionsCheckoutUserID '90400000-0000-0000-0000-000000000034'
\set questionsInvitedUserID '90400000-0000-0000-0000-000000000033'
\set userEmptyID '00000000-0000-0000-0000-000000000099'
\set userID '00000000-0000-0000-0000-000000000081'
\set userPaidID '00000000-0000-0000-0000-000000000082'

\set eventAID '00000000-0000-0000-0000-000000000101'
\set eventBID '00000000-0000-0000-0000-000000000102'
\set eventCanceledID '00000000-0000-0000-0000-000000000103'
\set eventCID '00000000-0000-0000-0000-000000000104'
\set eventDeletedID '00000000-0000-0000-0000-000000000105'
\set eventInactiveGroupID '00000000-0000-0000-0000-000000000106'
\set eventNoStartsAtID '00000000-0000-0000-0000-000000000107'
\set eventPastID '00000000-0000-0000-0000-000000000108'
\set eventPendingInvitationID '00000000-0000-0000-0000-000000000111'
\set eventPaidID '00000000-0000-0000-0000-000000000112'
\set eventPaidPriceWindowID '00000000-0000-0000-0000-000000000115'
\set eventPaidPurchaseID '00000000-0000-0000-0000-000000000113'
\set eventPaidTicketTypeID '00000000-0000-0000-0000-000000000114'
\set eventQuestionsID '90400000-0000-0000-0000-000000000041'
\set eventQuestionsTicketTypeID '90400000-0000-0000-0000-000000000081'
\set eventUnpublishedID '00000000-0000-0000-0000-000000000109'
\set eventDeletedGroupID '00000000-0000-0000-0000-000000000110'

\set sessionAID '00000000-0000-0000-0000-000000000201'
\set sessionCID '00000000-0000-0000-0000-000000000202'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (
        :'communityID',
        'community-one',
        'Community One',
        'Test community',
        'https://e/logo.png',
        'https://e/banner-mobile.png',
        'https://e/banner.png'
    );

-- Group category
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Meetup');

-- Groups
insert into "group" (group_id, active, community_id, deleted, group_category_id, name, slug) values
    (:'groupDeletedID', false, :'communityID', true, :'groupCategoryID', 'Deleted Group', 'deleted-group'),
    (:'groupID', true, :'communityID', false, :'groupCategoryID', 'Main Group', 'main-group'),
    (:'groupInactiveID', false, :'communityID', false, :'groupCategoryID', 'Inactive Group', 'inactive-group');

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username, name) values
    (:'userID', 'auth-hash', 'alice@example.com', true, 'alice', 'Alice'),
    (:'userPaidID', 'paid-auth-hash', 'paid@example.com', true, 'paid', 'Paid User'),
    (:'questionsAttendeeUserID', 'h', 'rq-attendee@test.com', true, 'rq-attendee', 'RQ Attendee'),
    (:'questionsCheckoutUserID', 'h', 'rq-checkout@test.com', true, 'rq-checkout', 'RQ Checkout'),
    (:'questionsCheckoutExpiredUserID', 'h', 'rq-expired@test.com', true, 'rq-expired', 'RQ Expired'),
    (:'questionsInvitedUserID', 'h', 'rq-invited@test.com', true, 'rq-invited', 'RQ Invited');

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
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    starts_at,
    registration_questions
) values (
    :'eventQuestionsID',
    :'groupID',
    'Questions Event',
    'questions-event',
    'd',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    now() + interval '1 day',
    '[{"id": "90400000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb
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
        '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Checkout answer"}]}'::jsonb
    ),
    (
        :'eventQuestionsID',
        :'questionsCheckoutExpiredUserID',
        false,
        'registration-questions-pending',
        '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Expired answer"}]}'::jsonb
    ),
    (
        :'eventQuestionsID',
        :'questionsAttendeeUserID',
        false,
        'confirmed',
        '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Attendee answer"}]}'::jsonb
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
                'can_cancel_attendance',
                false,
                'can_complete_registration_questions',
                false,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventAID'::uuid)::jsonb,
                'pending_payment',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'communityID'::uuid, :'eventAID'::uuid)::jsonb,
                'registration_questions_pending',
                false,
                'resume_checkout_url',
                null,
                'roles',
                jsonb_build_array('Attendee', 'Host', 'Speaker')
            ),
            jsonb_build_object(
                'can_cancel_attendance',
                true,
                'can_complete_registration_questions',
                false,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventBID'::uuid)::jsonb,
                'pending_payment',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'communityID'::uuid, :'eventBID'::uuid)::jsonb,
                'registration_questions_pending',
                false,
                'resume_checkout_url',
                null,
                'roles',
                jsonb_build_array('Attendee')
            ),
            jsonb_build_object(
                'can_cancel_attendance',
                false,
                'can_complete_registration_questions',
                false,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventCID'::uuid)::jsonb,
                'pending_payment',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'communityID'::uuid, :'eventCID'::uuid)::jsonb,
                'registration_questions_pending',
                false,
                'resume_checkout_url',
                null,
                'roles',
                jsonb_build_array('Speaker')
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
    jsonb_build_array('Attendee', 'Host', 'Speaker'),
    'Should deduplicate roles per event'
);

-- Should paginate events and keep total count
select is(
    list_user_events(:'userID'::uuid, '{"limit": 1, "offset": 1}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        jsonb_build_array(
            jsonb_build_object(
                'can_cancel_attendance',
                true,
                'can_complete_registration_questions',
                false,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventBID'::uuid)::jsonb,
                'pending_payment',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'communityID'::uuid, :'eventBID'::uuid)::jsonb,
                'registration_questions_pending',
                false,
                'resume_checkout_url',
                null,
                'roles',
                jsonb_build_array('Attendee')
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
                'can_cancel_attendance',
                false,
                'can_complete_registration_questions',
                false,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventPaidID'::uuid)::jsonb,
                'pending_payment',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'communityID'::uuid, :'eventPaidID'::uuid)::jsonb,
                'registration_questions_pending',
                false,
                'resume_checkout_url',
                null,
                'roles',
                jsonb_build_array('Attendee')
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

-- Should include pending registration events in the user dashboard
select is(
    list_user_events(:'questionsInvitedUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb #>> '{events,0,registration_questions_pending}',
    'true',
    'Should include pending registration events in the user dashboard'
);

-- Should allow pending users to complete registration questions from the user dashboard
select is(
    list_user_events(:'questionsInvitedUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb #>> '{events,0,can_complete_registration_questions}',
    'true',
    'Should allow pending users to complete registration questions from the user dashboard'
);

-- Should allow confirmed attendees to edit answers before the event starts
select is(
    list_user_events(:'questionsAttendeeUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb #>> '{events,0,can_complete_registration_questions}',
    'true',
    'Should allow confirmed attendees to edit answers before the event starts'
);

-- Should report active pending checkout before pending registration questions
select is(
    (
        list_user_events(:'questionsCheckoutUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
    ) - 'event' - 'registration_answers' - 'registration_questions',
    jsonb_build_object(
        'can_cancel_attendance',
        false,
        'can_complete_registration_questions',
        false,
        'pending_payment',
        true,
        'registration_questions_pending',
        false,
        'resume_checkout_url',
        'https://example.test/checkout/resume',
        'roles',
        jsonb_build_array('Payment pending')
    ),
    'Should report active pending checkout before pending registration questions'
);

-- Should ignore expired pending checkout before pending registration questions
select is(
    (
        list_user_events(:'questionsCheckoutExpiredUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
    ) - 'event' - 'registration_answers' - 'registration_questions',
    jsonb_build_object(
        'can_cancel_attendance',
        false,
        'can_complete_registration_questions',
        true,
        'pending_payment',
        false,
        'registration_questions_pending',
        true,
        'resume_checkout_url',
        null,
        'roles',
        jsonb_build_array('Registration pending')
    ),
    'Should ignore expired pending checkout before pending registration questions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
