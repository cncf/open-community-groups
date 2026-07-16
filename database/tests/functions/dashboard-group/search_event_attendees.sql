-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(26);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set abandonedCheckoutPurchaseID '3a2e0000-0000-0000-0000-000000000061'
\set abandonedCheckoutUserID '3a2e0000-0000-0000-0000-000000000062'
\set attendanceFilterEventID '3a2e0000-0000-0000-0000-000000000030'
\set communityID '3a2e0000-0000-0000-0000-000000000001'
\set event1ID '3a2e0000-0000-0000-0000-000000000002'
\set event2ID '3a2e0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a2e0000-0000-0000-0000-000000000004'
\set eventDiscountCode1ID '3a2e0000-0000-0000-0000-000000000005'
\set eventPurchase1ID '3a2e0000-0000-0000-0000-000000000006'
\set eventPurchase2ID '3a2e0000-0000-0000-0000-000000000007'
\set eventPurchasePendingCheckoutID '3a2e0000-0000-0000-0000-000000000025'
\set eventPendingCheckoutID '3a2e0000-0000-0000-0000-000000000026'
\set eventQuestionsID '3a2e0000-0000-0000-0000-000000000008'
\set eventRefundRequest2ID '3a2e0000-0000-0000-0000-000000000009'
\set eventStopwordSearchID '3a2e0000-0000-0000-0000-000000000028'
\set eventTicketType1ID '3a2e0000-0000-0000-0000-000000000010'
\set eventTicketType2ID '3a2e0000-0000-0000-0000-000000000011'
\set eventTicketTypePendingCheckoutID '3a2e0000-0000-0000-0000-000000000027'
\set group2ID '3a2e0000-0000-0000-0000-000000000012'
\set groupCategoryID '3a2e0000-0000-0000-0000-000000000013'
\set groupID '3a2e0000-0000-0000-0000-000000000014'
\set missingEventID '3a2e0000-0000-0000-0000-000000000015'
\set pendingCheckoutUserID '3a2e0000-0000-0000-0000-000000000024'
\set questionsAttendeeUserID '3a2e0000-0000-0000-0000-000000000016'
\set progressClaimID '3a2e0000-0000-0000-0000-000000000060'
\set progressPurchase1ID '3a2e0000-0000-0000-0000-000000000040'
\set progressPurchase2ID '3a2e0000-0000-0000-0000-000000000041'
\set progressPurchase3ID '3a2e0000-0000-0000-0000-000000000042'
\set progressPurchase4ID '3a2e0000-0000-0000-0000-000000000043'
\set progressPurchase5ID '3a2e0000-0000-0000-0000-000000000044'
\set progressPurchase6ID '3a2e0000-0000-0000-0000-000000000045'
\set progressPurchase7ID '3a2e0000-0000-0000-0000-000000000046'
\set progressPurchase8ID '3a2e0000-0000-0000-0000-000000000047'
\set progressPurchase9ID '3a2e0000-0000-0000-0000-000000000048'
\set progressPurchase10ID '3a2e0000-0000-0000-0000-000000000049'
\set progressPurchase11ID '3a2e0000-0000-0000-0000-000000000050'
\set progressRefund1ID '3a2e0000-0000-0000-0000-000000000051'
\set progressRefund2ID '3a2e0000-0000-0000-0000-000000000052'
\set progressRefund3ID '3a2e0000-0000-0000-0000-000000000053'
\set progressRefund4ID '3a2e0000-0000-0000-0000-000000000054'
\set progressRefund5ID '3a2e0000-0000-0000-0000-000000000055'
\set progressRefund6ID '3a2e0000-0000-0000-0000-000000000056'
\set progressRefund7ID '3a2e0000-0000-0000-0000-000000000057'
\set progressRefund8ID '3a2e0000-0000-0000-0000-000000000058'
\set progressRefund9ID '3a2e0000-0000-0000-0000-000000000059'
\set progressUser7ID '3a2e0000-0000-0000-0000-000000000033'
\set progressUser8ID '3a2e0000-0000-0000-0000-000000000034'
\set registrationQuestionID '3a2e0000-0000-0000-0000-000000000017'
\set refundProgressEventID '3a2e0000-0000-0000-0000-000000000031'
\set refundProgressTicketTypeID '3a2e0000-0000-0000-0000-000000000032'
\set user1ID '3a2e0000-0000-0000-0000-000000000018'
\set user2ID '3a2e0000-0000-0000-0000-000000000019'
\set user3ID '3a2e0000-0000-0000-0000-000000000020'
\set user4ID '3a2e0000-0000-0000-0000-000000000021'
\set user5ID '3a2e0000-0000-0000-0000-000000000022'
\set user6ID '3a2e0000-0000-0000-0000-000000000023'
\set userStopwordSearchID '3a2e0000-0000-0000-0000-000000000029'

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
    'attendee-search-community',
    'Attendee Search Community',
    'A test community for attendee search',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Attendee Group', 'attendee-group'),
    (:'group2ID', :'communityID', :'groupCategoryID', 'Other Group', 'other-group');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    bio,
    email,
    email_verified,
    github_url,
    optional_notifications_enabled,
    provider,
    username,
    website_url,

    company,
    name,
    photo_url,
    registration_status,
    title
)
values (
    :'user1ID',
    gen_random_bytes(32),
    'Maintains event infrastructure',
    'alice@example.com',
    true,
    'https://github.com/alice',
    true,
    '{"github": {"username": "alice-gh", "private": "secret"}, "linuxfoundation": {"username": "alice-lf", "subject": "secret"}}'::jsonb,
    'alice',
    'https://example.com/alice',
    'Cloud Corp',
    'Alice',
    'https://example.com/alice.png',
    'registered',
    'Principal Engineer'
), (
    :'user2ID',
    gen_random_bytes(32),
    null,
    'bob@example.com',
    true,
    null,
    false,
    null,
    'bob',
    null,
    null,
    null,
    'https://example.com/bob.png',
    'registered',
    null
), (
    :'user3ID',
    gen_random_bytes(32),
    null,
    'pending@example.com',
    false,
    null,
    true,
    null,
    'pending',
    null,
    null,
    'Pending Invite',
    null,
    'pre-registered',
    null
), (
    :'user4ID',
    gen_random_bytes(32),
    null,
    'rejected@example.com',
    true,
    null,
    true,
    null,
    'rejected',
    null,
    null,
    'Rejected Invite',
    null,
    'registered',
    null
), (
    :'user5ID',
    gen_random_bytes(32),
    null,
    'canceled@example.com',
    true,
    null,
    true,
    null,
    'canceled',
    null,
    null,
    'Canceled Invite',
    null,
    'registered',
    null
), (
    :'user6ID',
    gen_random_bytes(32),
    null,
    'questions-pending@example.com',
    true,
    null,
    true,
    null,
    'questions-pending',
    null,
    null,
    'Questions Pending',
    null,
    'registered',
    null
), (
    :'pendingCheckoutUserID',
    gen_random_bytes(32),
    null,
    'pending-checkout@example.com',
    true,
    null,
    true,
    null,
    'pending-checkout',
    null,
    null,
    'Pending Checkout',
    null,
    'registered',
    null
), (
    :'questionsAttendeeUserID',
    gen_random_bytes(32),
    null,
    'rq-attendee@test.com',
    false,
    null,
    true,
    null,
    'rq-attendee',
    null,
    null,
    null,
    null,
    'registered',
    null
), (
    :'userStopwordSearchID',
    gen_random_bytes(32),
    null,
    'may@example.com',
    true,
    null,
    true,
    null,
    'may',
    null,
    null,
    'May',
    null,
    'registered',
    null
);

-- Users completing the refund progress and abandoned checkout scenarios
insert into "user" (auth_hash, email, user_id, username) values
    (gen_random_bytes(32), 'abandoned-checkout@example.test', :'abandonedCheckoutUserID', 'abandoned-checkout'),
    (gen_random_bytes(32), 'progress-7@example.test', :'progressUser7ID', 'progress-7'),
    (gen_random_bytes(32), 'progress-8@example.test', :'progressUser8ID', 'progress-8');

-- Events
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    payment_currency_code,
    published,
    canceled,
    deleted
)
values (
    :'event1ID',
    'Attendee Event',
    'attendee-event',
    'An event for attendee search',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    false
), (
    :'event2ID',
    'Refund Event',
    'refund-event',
    'An event for attendee refunds',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    false
), (
    :'eventPendingCheckoutID',
    'Pending Checkout Event',
    'pending-checkout-event',
    'An event with an active pending checkout',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    false
), (
    :'eventStopwordSearchID',
    'Stopword Search Event',
    'stopword-search-event',
    'An event with an attendee whose name looks like a stop word',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    false
), (
    :'attendanceFilterEventID',
    'Attendance Filter Event',
    'attendance-filter-event',
    'An event for attendance state filters',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    false
), (
    :'refundProgressEventID',
    'Refund Progress Event',
    'refund-progress-event',
    'A canceled event with every refund progress state',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    true,
    false
);

-- Event with registration questions used to return attendee answers
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
    'An event with registration questions',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    '2030-01-01 10:00:00+00',
    jsonb_build_array(jsonb_build_object(
        'id', :'registrationQuestionID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    ))
);

-- Ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
)
values
    (:'eventTicketType1ID', :'event1ID', 1, 100, 'General admission'),
    (:'eventTicketType2ID', :'event2ID', 1, 100, 'VIP'),
    (:'eventTicketTypePendingCheckoutID', :'eventPendingCheckoutID', 1, 100, 'General admission'),
    (:'refundProgressTicketTypeID', :'refundProgressEventID', 1, 100, 'Refund progress');

-- Discount codes
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    event_id,
    kind,
    title
)
values (
    :'eventDiscountCode1ID',
    500,
    'SAVE5',
    :'event1ID',
    'fixed_amount',
    'Launch discount'
);

-- Attendees
insert into event_attendee (
    event_id,
    user_id,
    checked_in,
    checked_in_at,
    created_at,
    manually_invited,
    status
) values (
    :'event1ID',
    :'user1ID',
    true,
    '2024-01-01 10:00:00+00',
    '2024-01-01 00:00:00+00',
    true,
    'confirmed'
), (
    :'event1ID',
    :'user2ID',
    false,
    null,
    '2024-01-02 00:00:00+00',
    false,
    'confirmed'
), (
    :'event1ID',
    :'user3ID',
    false,
    null,
    '2024-01-03 00:00:00+00',
    true,
    'invitation-pending'
), (
    :'event1ID',
    :'user4ID',
    false,
    null,
    '2024-01-04 00:00:00+00',
    true,
    'invitation-rejected'
), (
    :'event1ID',
    :'user5ID',
    false,
    null,
    '2024-01-05 00:00:00+00',
    true,
    'invitation-canceled'
), (
    :'event1ID',
    :'user6ID',
    false,
    null,
    '2024-01-06 00:00:00+00',
    false,
    'registration-questions-pending'
), (
    :'eventPendingCheckoutID',
    :'pendingCheckoutUserID',
    false,
    null,
    '2024-01-07 00:00:00+00',
    false,
    'registration-questions-pending'
), (
    :'event2ID',
    :'user2ID',
    true,
    '2024-01-03 15:00:00+00',
    '2024-01-03 00:00:00+00',
    false,
    'confirmed'
), (
    :'eventStopwordSearchID',
    :'userStopwordSearchID',
    false,
    null,
    '2024-01-08 00:00:00+00',
    false,
    'confirmed'
);

-- Attendee with registration answers returned by attendee search
insert into event_attendee (event_id, user_id, status, registration_answers)
values (
    :'eventQuestionsID',
    :'questionsAttendeeUserID',
    'confirmed',
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', :'registrationQuestionID',
            'value', 'Attendee answer'
        ))
    )
);

-- Active and canceled attendees used to verify attendance filters
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values
    (null, null, :'attendanceFilterEventID', 'confirmed', :'user1ID'),
    (current_timestamp, :'user2ID', :'attendanceFilterEventID', 'attendance-canceled', :'user2ID');

-- Canceled attendees exposing refund progress and abandoned checkout states
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values
    (current_timestamp, :'abandonedCheckoutUserID', :'refundProgressEventID', 'attendance-canceled', :'abandonedCheckoutUserID'),
    (current_timestamp, :'user1ID', :'refundProgressEventID', 'attendance-canceled', :'user1ID'),
    (current_timestamp, :'user2ID', :'refundProgressEventID', 'attendance-canceled', :'user2ID'),
    (current_timestamp, :'user3ID', :'refundProgressEventID', 'attendance-canceled', :'user3ID'),
    (current_timestamp, :'user4ID', :'refundProgressEventID', 'attendance-canceled', :'user4ID'),
    (current_timestamp, :'user5ID', :'refundProgressEventID', 'attendance-canceled', :'user5ID'),
    (current_timestamp, :'user6ID', :'refundProgressEventID', 'attendance-canceled', :'user6ID'),
    (current_timestamp, :'pendingCheckoutUserID', :'refundProgressEventID', 'attendance-canceled', :'pendingCheckoutUserID'),
    (current_timestamp, :'questionsAttendeeUserID', :'refundProgressEventID', 'attendance-canceled', :'questionsAttendeeUserID'),
    (current_timestamp, :'userStopwordSearchID', :'refundProgressEventID', 'attendance-canceled', :'userStopwordSearchID'),
    (current_timestamp, :'progressUser7ID', :'refundProgressEventID', 'attendance-canceled', :'progressUser7ID'),
    (current_timestamp, :'progressUser8ID', :'refundProgressEventID', 'attendance-canceled', :'progressUser8ID');

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
)
values
    (
        :'eventPurchase1ID',
        2500,
        'USD',
        500,
        'SAVE5',
        :'eventDiscountCode1ID',
        :'event1ID',
        :'eventTicketType1ID',
        null,
        'completed',
        'General admission',
        :'user1ID'
    ),
    (
        :'eventPurchase2ID',
        4000,
        'USD',
        0,
        null,
        null,
        :'event2ID',
        :'eventTicketType2ID',
        null,
        'refund-requested',
        'VIP',
        :'user2ID'
    ),
    (
        :'eventPurchasePendingCheckoutID',
        2500,
        'USD',
        0,
        null,
        null,
        :'eventPendingCheckoutID',
        :'eventTicketTypePendingCheckoutID',
        current_timestamp + interval '10 minutes',
        'pending',
        'General admission',
        :'pendingCheckoutUserID'
    );

-- Refund requests
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
)
values (
    :'eventRefundRequest2ID',
    :'eventPurchase2ID',
    :'user2ID',
    'pending'
);

-- Purchases representing abandoned checkout, active checkout, and worker-controlled progress
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    hold_expires_at,
    payment_provider_id,
    provider_payment_reference,
    refunded_at
) values
    (2500, 'USD', :'refundProgressEventID', :'abandonedCheckoutPurchaseID', :'refundProgressTicketTypeID', 'pending', 'Refund progress', :'abandonedCheckoutUserID', current_timestamp - interval '10 minutes', 'stripe', null, null),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase1ID', :'refundProgressTicketTypeID', 'pending', 'Refund progress', :'user1ID', current_timestamp + interval '10 minutes', 'stripe', null, null),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase2ID', :'refundProgressTicketTypeID', 'refunded', 'Refund progress', :'user2ID', null, 'stripe', 'pi_progress_2', current_timestamp),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase3ID', :'refundProgressTicketTypeID', 'refunded', 'Refund progress', :'user3ID', null, 'stripe', 'pi_progress_3', current_timestamp),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase4ID', :'refundProgressTicketTypeID', 'refund-pending', 'Refund progress', :'user4ID', null, 'stripe', 'pi_progress_4', null),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase5ID', :'refundProgressTicketTypeID', 'refund-pending', 'Refund progress', :'user5ID', null, 'stripe', 'pi_progress_5', null),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase6ID', :'refundProgressTicketTypeID', 'refund-pending', 'Refund progress', :'user6ID', null, 'stripe', 'pi_progress_6', null),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase7ID', :'refundProgressTicketTypeID', 'refund-pending', 'Refund progress', :'pendingCheckoutUserID', null, 'stripe', 'pi_progress_7', null),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase8ID', :'refundProgressTicketTypeID', 'refund-pending', 'Refund progress', :'questionsAttendeeUserID', null, 'stripe', 'pi_progress_8', null),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase9ID', :'refundProgressTicketTypeID', 'refund-recovery-pending', 'Refund progress', :'userStopwordSearchID', null, 'stripe', 'pi_progress_9', null),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase10ID', :'refundProgressTicketTypeID', 'refund-pending', 'Refund progress', :'progressUser7ID', null, 'stripe', 'pi_progress_10', null),
    (2500, 'USD', :'refundProgressEventID', :'progressPurchase11ID', :'refundProgressTicketTypeID', 'refund-pending', 'Refund progress', :'progressUser8ID', null, 'stripe', 'pi_progress_11', null);

-- Durable refunds representing every provider progress branch
insert into event_purchase_refund (
    amount_minor,
    attempt_count,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,
    terminal_failure,

    claim_id,
    claimed_at,
    finalized_at,
    provider_refund_id,
    provider_refunded_at
) values
    (2500, 0, 'USD', :'progressPurchase3ID', :'progressRefund1ID', 'progress-refund-1', 'event-cancellation', 'stripe', 'finalized', false, null, null, current_timestamp, 're_progress_1', current_timestamp),
    (2500, 1, 'USD', :'progressPurchase4ID', :'progressRefund2ID', 'progress-refund-2', 'event-cancellation', 'stripe', 'processing', false, :'progressClaimID', current_timestamp, null, null, null),
    (2500, 1, 'USD', :'progressPurchase5ID', :'progressRefund3ID', 'progress-refund-3', 'event-cancellation', 'stripe', 'provider-succeeded', false, null, null, null, 're_progress_3', current_timestamp),
    (2500, 10, 'USD', :'progressPurchase6ID', :'progressRefund4ID', 'progress-refund-4', 'event-cancellation', 'stripe', 'provider-pending', false, null, null, null, null, null),
    (2500, 1, 'USD', :'progressPurchase7ID', :'progressRefund5ID', 'progress-refund-5', 'event-cancellation', 'stripe', 'provider-pending', false, null, null, null, 're_progress_5', null),
    (2500, 1, 'USD', :'progressPurchase8ID', :'progressRefund6ID', 'progress-refund-6', 'event-cancellation', 'stripe', 'provider-pending', false, null, null, null, null, null),
    (2500, 1, 'USD', :'progressPurchase9ID', :'progressRefund7ID', 'progress-refund-7', 'event-cancellation', 'stripe', 'provider-failed', true, null, null, null, 're_progress_7', null),
    (2500, 10, 'USD', :'progressPurchase10ID', :'progressRefund8ID', 'progress-refund-8', 'event-cancellation', 'stripe', 'provider-failed', false, null, null, null, null, null),
    (2500, 1, 'USD', :'progressPurchase11ID', :'progressRefund9ID', 'progress-refund-9', 'event-cancellation', 'stripe', 'provider-failed', false, null, null, null, null, null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should default to active attendance for an active event
select results_eq(
    format($$
        with payload as (
            select search_event_attendees(
                %L::uuid,
                %L::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb as value
        )
        select
            value#>>'{attendees,0,user,user_id}',
            (value->>'total')::int
        from payload
    $$, :'groupID', :'attendanceFilterEventID'),
    format($$ values (%L::text, 1) $$, :'user1ID'),
    'Should default to active attendance for an active event'
);

-- Should default to all attendance for a canceled event
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'refundProgressEventID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb->>'total',
    '12',
    'Should default to all attendance for a canceled event'
);

-- Should expose every refund progress state
select is(
    (
        select jsonb_object_agg(
            attendee#>>'{user,user_id}',
            attendee->>'refund_progress'
        )
        from jsonb_array_elements(
            search_event_attendees(
                :'groupID'::uuid,
                :'refundProgressEventID'::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb->'attendees'
        ) attendee
    ),
    jsonb_build_object(
        :'abandonedCheckoutUserID', null,
        :'pendingCheckoutUserID', 'processing',
        :'progressUser7ID', 'retryable-failure',
        :'progressUser8ID', 'queued',
        :'questionsAttendeeUserID', 'queued',
        :'user1ID', 'awaiting-checkout',
        :'user2ID', 'refunded',
        :'user3ID', 'refunded',
        :'user4ID', 'processing',
        :'user5ID', 'processing',
        :'user6ID', 'retryable-failure',
        :'userStopwordSearchID', 'recovery-required'
    ),
    'Should expose every refund progress state'
);

-- Should omit refund progress for an abandoned pending checkout
select ok(
    (
        select not (attendee ? 'refund_progress')
        from jsonb_array_elements(
            search_event_attendees(
                :'groupID'::uuid,
                :'refundProgressEventID'::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb->'attendees'
        ) attendee
        where attendee#>>'{user,user_id}' = :'abandonedCheckoutUserID'
    ),
    'Should omit refund progress for an abandoned pending checkout'
);

-- Should filter explicitly for active attendance
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'refundProgressEventID'::uuid,
        '{"attendance": "active", "limit": 50, "offset": 0}'::jsonb
    )::jsonb->>'total',
    '0',
    'Should filter explicitly for active attendance'
);

-- Should filter explicitly for all attendance
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'attendanceFilterEventID'::uuid,
        '{"attendance": "all", "limit": 50, "offset": 0}'::jsonb
    )::jsonb->>'total',
    '2',
    'Should filter explicitly for all attendance'
);

-- Should filter explicitly for canceled attendance
select results_eq(
    format($$
        with payload as (
            select search_event_attendees(
                %L::uuid,
                %L::uuid,
                '{"attendance": "canceled", "limit": 50, "offset": 0}'::jsonb
            )::jsonb as value
        )
        select
            value#>>'{attendees,0,user,user_id}',
            (value->>'total')::int
        from payload
    $$, :'groupID', :'attendanceFilterEventID'),
    format($$ values (%L::text, 1) $$, :'user2ID'),
    'Should filter explicitly for canceled attendance'
);

-- Should ignore an invalid attendance filter and use the event default
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'refundProgressEventID'::uuid,
        '{"attendance": "unknown", "limit": 50, "offset": 0}'::jsonb
    )::jsonb->>'total',
    '12',
    'Should ignore an invalid attendance filter and use the event default'
);

-- Should return attendees for event1 with expected fields and order
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"can_receive_attendee_email": true, "checked_in": true,  "created_at": 1704067200, "email": "alice@example.com", "manually_invited": true, "registration_answers": null, "status": "confirmed", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000018", "username": "alice", "bio": "Maintains event infrastructure", "company": "Cloud Corp", "github_url": "https://github.com/alice", "name": "Alice", "photo_url": "https://example.com/alice.png", "provider": {"github": {"username": "alice-gh"}, "linuxfoundation": {"username": "alice-lf"}}, "title": "Principal Engineer", "website_url": "https://example.com/alice"}, "checked_in_at": 1704103200, "amount_minor": 2500, "currency_code": "USD", "discount_code": "SAVE5", "event_purchase_id": "3a2e0000-0000-0000-0000-000000000006", "refund_request_status": null, "ticket_title": "General admission"},
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob", "photo_url": "https://example.com/bob.png"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null},
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704240000, "email": "pending@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-pending", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000020", "username": "pending", "name": "Pending Invite"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null},
            {"can_receive_attendee_email": true, "checked_in": false, "created_at": 1704499200, "email": "questions-pending@example.com", "manually_invited": false, "registration_answers": null, "status": "registration-questions-pending", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000023", "username": "questions-pending", "name": "Questions Pending"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null},
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704326400, "email": "rejected@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-rejected", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000021", "username": "rejected", "name": "Rejected Invite"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null}
        ]'::jsonb,
        'all_attendees_email_recipient_total', 2,
        'total', 5
    ),
    'Should return attendees for event1 with expected fields and order'
);

-- Should return paginated attendees when limit and offset are provided
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 1, 'offset', 1)
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob", "photo_url": "https://example.com/bob.png"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null}
        ]'::jsonb,
        'all_attendees_email_recipient_total', 2,
        'total', 5
    ),
    'Should return paginated attendees when limit and offset are provided'
);

-- Should return full attendee list when pagination is omitted
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object()
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"can_receive_attendee_email": true, "checked_in": true,  "created_at": 1704067200, "email": "alice@example.com", "manually_invited": true, "registration_answers": null, "status": "confirmed", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000018", "username": "alice", "bio": "Maintains event infrastructure", "company": "Cloud Corp", "github_url": "https://github.com/alice", "name": "Alice", "photo_url": "https://example.com/alice.png", "provider": {"github": {"username": "alice-gh"}, "linuxfoundation": {"username": "alice-lf"}}, "title": "Principal Engineer", "website_url": "https://example.com/alice"}, "checked_in_at": 1704103200, "amount_minor": 2500, "currency_code": "USD", "discount_code": "SAVE5", "event_purchase_id": "3a2e0000-0000-0000-0000-000000000006", "refund_request_status": null, "ticket_title": "General admission"},
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob", "photo_url": "https://example.com/bob.png"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null},
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704240000, "email": "pending@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-pending", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000020", "username": "pending", "name": "Pending Invite"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null},
            {"can_receive_attendee_email": true, "checked_in": false, "created_at": 1704499200, "email": "questions-pending@example.com", "manually_invited": false, "registration_answers": null, "status": "registration-questions-pending", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000023", "username": "questions-pending", "name": "Questions Pending"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null},
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704326400, "email": "rejected@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-rejected", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000021", "username": "rejected", "name": "Rejected Invite"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null}
        ]'::jsonb,
        'all_attendees_email_recipient_total', 2,
        'total', 5
    ),
    'Should return full attendee list when pagination is omitted'
);

-- Should return attendees for event2
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event2ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"can_receive_attendee_email": false, "checked_in": true, "created_at": 1704240000, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob", "photo_url": "https://example.com/bob.png"}, "checked_in_at": 1704294000, "amount_minor": 4000, "currency_code": "USD", "discount_code": null, "event_purchase_id": "3a2e0000-0000-0000-0000-000000000007", "refund_request_status": "pending", "ticket_title": "VIP"}
        ]'::jsonb,
        'all_attendees_email_recipient_total', 0,
        'total', 1
    ),
    'Should return attendees for event2'
);

-- Should return empty list when event scope is null
select is(
    search_event_attendees(
        :'groupID'::uuid,
        null::uuid,
        '{"limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'all_attendees_email_recipient_total', 0,
        'attendees', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event scope is null'
);

-- Should return empty list for non-existing event
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'missingEventID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'all_attendees_email_recipient_total', 0,
        'attendees', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- Should return empty list when event belongs to another group
select is(
    search_event_attendees(
        :'group2ID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'all_attendees_email_recipient_total', 0,
        'attendees', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event belongs to another group'
);

-- Should filter attendees by identity search query without changing all-recipient count
select ok(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'ali'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and (data->>'all_attendees_email_recipient_total')::int = 2
        and data#>>'{attendees,0,user,user_id}' = :'user1ID'
        from result
    ),
    'Should filter attendees by identity search query without changing all-recipient count'
);

-- Should filter attendees whose names look like stop words
select ok(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'eventStopwordSearchID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'may'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and (data->>'all_attendees_email_recipient_total')::int = 1
        and data#>>'{attendees,0,user,user_id}' = :'userStopwordSearchID'
        from result
    ),
    'Should filter attendees whose names look like stop words'
);

-- Should filter attendees by company search query
select ok(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'cloud corp'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and (data->>'all_attendees_email_recipient_total')::int = 2
        and data#>>'{attendees,0,user,user_id}' = :'user1ID'
        from result
    ),
    'Should filter attendees by company search query'
);

-- Should filter attendees by title search query
select ok(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'principal engineer'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and (data->>'all_attendees_email_recipient_total')::int = 2
        and data#>>'{attendees,0,user,user_id}' = :'user1ID'
        from result
    ),
    'Should filter attendees by title search query'
);

-- Should sort attendees by RSVP date descending
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'sort', 'created-at-desc'
        )
    )::jsonb#>>'{attendees,0,user,username}',
    'questions-pending',
    'Should sort attendees by created_at descending'
);

-- Should filter attendees with a user title
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'title', 'present'
        )
    )::jsonb->>'total',
    '1',
    'Should filter attendees with a title'
);

-- Should filter attendees without a user title
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'title', 'missing'
        )
    )::jsonb->>'total',
    '4',
    'Should filter attendees without a title'
);

-- Should filter attendees by checked_in status
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'checked_in', true,
            'limit', 50,
            'offset', 0
        )
    )::jsonb->>'total',
    '1',
    'Should filter attendees by checked_in status'
);

-- Should filter attendees by event ticket type identifiers
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'event_ticket_type_ids', jsonb_build_array(:'eventTicketType1ID'::uuid),
            'limit', 50,
            'offset', 0
        )
    )::jsonb->>'total',
    '1',
    'Should filter attendees by event ticket type identifiers'
);

-- Should exclude active pending checkout holds from email recipient eligibility
select ok(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'eventPendingCheckoutID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and (data->>'all_attendees_email_recipient_total')::int = 0
        and (data#>>'{attendees,0,can_receive_attendee_email}')::boolean = false
        from result
    ),
    'Should exclude active pending checkout holds from email recipient eligibility'
);

-- Should include registration answers in attendee search results
select is(
    (
        select attendee->'registration_answers'
        from jsonb_array_elements(
            search_event_attendees(:'groupID'::uuid, :'eventQuestionsID'::uuid, jsonb_build_object('limit', 10, 'offset', 0))::jsonb->'attendees'
        ) attendee
        where attendee#>>'{user,user_id}' = :'questionsAttendeeUserID'
    ),
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', :'registrationQuestionID',
            'value', 'Attendee answer'
        ))
    ),
    'Should include registration answers in attendee search results'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
