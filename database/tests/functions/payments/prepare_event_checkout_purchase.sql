-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeUserID '79100000-0000-0000-0000-000000000022'
\set checkoutUserID '79100000-0000-0000-0000-000000000023'
\set communityID '79100000-0000-0000-0000-000000000001'
\set completedPurchaseID '79100000-0000-0000-0000-000000000019'
\set completedUserID '79100000-0000-0000-0000-000000000024'
\set discountUserID '79100000-0000-0000-0000-000000000028'
\set eventCategoryID '79100000-0000-0000-0000-000000000002'
\set exhaustedDiscountUserID '79100000-0000-0000-0000-000000000027'
\set freeDiscountID '79100000-0000-0000-0000-000000000016'
\set groupCategoryID '79100000-0000-0000-0000-000000000010'
\set groupID '79100000-0000-0000-0000-000000000011'
\set inactiveDiscountID '79100000-0000-0000-0000-000000000017'
\set inactiveEventID '79100000-0000-0000-0000-000000000005'
\set inactivePriceWindowID '79100000-0000-0000-0000-000000000015'
\set inactiveTicketTypeID '79100000-0000-0000-0000-000000000009'
\set inactiveUserID '79100000-0000-0000-0000-000000000030'
\set invalidDiscountUserID '79100000-0000-0000-0000-000000000025'
\set invitedPendingPurchaseID '79100000-0000-0000-0000-000000000040'
\set invitedUserID '79100000-0000-0000-0000-000000000039'
\set limitedDiscountID '79100000-0000-0000-0000-000000000018'
\set mainEventID '79100000-0000-0000-0000-000000000003'
\set priceWindowAID '79100000-0000-0000-0000-000000000012'
\set priceWindowBID '79100000-0000-0000-0000-000000000013'
\set questionsEventID '79100000-0000-0000-0000-000000000035'
\set questionsPriceWindowID '79100000-0000-0000-0000-000000000036'
\set questionsTicketTypeID '79100000-0000-0000-0000-000000000037'
\set questionsUserID '79100000-0000-0000-0000-000000000038'
\set redeemedPurchaseID '79100000-0000-0000-0000-000000000020'
\set redeemedUserID '79100000-0000-0000-0000-000000000031'
\set registrationQuestionID '79100000-0000-0000-0000-000000000101'
\set soldOutEventID '79100000-0000-0000-0000-000000000004'
\set soldOutHolderUserID '79100000-0000-0000-0000-000000000032'
\set soldOutPriceWindowID '79100000-0000-0000-0000-000000000014'
\set soldOutPurchaseID '79100000-0000-0000-0000-000000000021'
\set soldOutTicketTypeID '79100000-0000-0000-0000-000000000008'
\set soldOutUserID '79100000-0000-0000-0000-000000000029'
\set ticketTypeAID '79100000-0000-0000-0000-000000000006'
\set ticketTypeBID '79100000-0000-0000-0000-000000000007'
\set unavailableDiscountUserID '79100000-0000-0000-0000-000000000026'
\set underMinimumDiscountID '79100000-0000-0000-0000-000000000034'
\set underMinimumUserID '79100000-0000-0000-0000-000000000033'

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
    'prepare-community',
    'Prepare Community',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'attendeeUserID', 'hash-1', 'attendee@example.com', true, 'attendee'),
    (:'checkoutUserID', 'hash-2', 'checkout@example.com', true, 'checkout-user'),
    (:'completedUserID', 'hash-3', 'completed@example.com', true, 'completed-user'),
    (:'invalidDiscountUserID', 'hash-4', 'invalid@example.com', true, 'invalid-user'),
    (:'unavailableDiscountUserID', 'hash-5', 'unavailable@example.com', true, 'unavailable-user'),
    (:'exhaustedDiscountUserID', 'hash-6', 'exhausted@example.com', true, 'exhausted-user'),
    (:'discountUserID', 'hash-7', 'discount@example.com', true, 'discount-user'),
    (:'soldOutUserID', 'hash-8', 'soldout@example.com', true, 'soldout-user'),
    (:'inactiveUserID', 'hash-9', 'inactive@example.com', true, 'inactive-user'),
    (:'redeemedUserID', 'hash-10', 'redeemed@example.com', true, 'redeemed-user'),
    (:'soldOutHolderUserID', 'hash-11', 'holder@example.com', true, 'holder-user'),
    (:'underMinimumUserID', 'hash-12', 'under-minimum@example.com', true, 'under-minimum-user'),
    (:'questionsUserID', 'hash-13', 'questions@example.com', true, 'questions-user'),
    (:'invitedUserID', 'hash-14', 'invited@example.com', true, 'invited-user');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    payment_recipient,
    slug_pretty
)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Prepare Group',
    'prepare-group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_prepare'),
    'prepare-group-pretty'
);

-- Events
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    starts_at,
    payment_currency_code,
    published,
    published_at,
    registration_questions
) values (
    :'mainEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Main Event',
    'main-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    'USD',
    true,
    now(),
    '[]'::jsonb
), (
    :'soldOutEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Sold Out Event',
    'sold-out-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    'USD',
    true,
    now(),
    '[]'::jsonb
), (
    :'inactiveEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Inactive Ticket Event',
    'inactive-ticket-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    'USD',
    true,
    now(),
    '[]'::jsonb
), (
    -- Event that requires registration answers before checkout can proceed
    :'questionsEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Questions Checkout Event',
    'questions-checkout-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    'USD',
    true,
    now(),
    jsonb_build_array(jsonb_build_object(
        'id', :'registrationQuestionID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    ))
);

-- Ticket types
insert into event_ticket_type (event_ticket_type_id, active, event_id, "order", seats_total, title)
values
    (:'ticketTypeAID', true, :'mainEventID', 1, 10, 'General admission'),
    (:'ticketTypeBID', true, :'mainEventID', 2, 10, 'VIP'),
    (:'soldOutTicketTypeID', true, :'soldOutEventID', 1, 1, 'General admission'),
    (:'inactiveTicketTypeID', false, :'inactiveEventID', 1, 10, 'General admission'),
    (:'questionsTicketTypeID', true, :'questionsEventID', 1, 10, 'General admission');

-- Price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'priceWindowAID', 2500, :'ticketTypeAID'),
    (:'priceWindowBID', 4000, :'ticketTypeBID'),
    (:'soldOutPriceWindowID', 2500, :'soldOutTicketTypeID'),
    (:'inactivePriceWindowID', 2500, :'inactiveTicketTypeID'),
    (:'questionsPriceWindowID', 2500, :'questionsTicketTypeID');

-- Discount codes
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    total_available,
    title
) values (
    :'freeDiscountID',
    true,
    2500,
    2,
    true,
    'FREEPASS',
    :'mainEventID',
    'fixed_amount',
    null,
    'Free pass'
), (
    :'inactiveDiscountID',
    false,
    500,
    1,
    true,
    'INACTIVE',
    :'mainEventID',
    'fixed_amount',
    null,
    'Inactive discount'
), (
    :'limitedDiscountID',
    true,
    500,
    5,
    true,
    'TOTAL1',
    :'mainEventID',
    'fixed_amount',
    1,
    'Limited discount'
), (
    :'underMinimumDiscountID',
    true,
    2475,
    5,
    true,
    'UNDERMIN',
    :'mainEventID',
    'fixed_amount',
    null,
    'Under minimum discount'
);

-- Existing attendee
insert into event_attendee (event_id, user_id)
values (:'mainEventID', :'attendeeUserID');

-- Attendee with a pending invitation alongside a reusable pending purchase
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'mainEventID', :'invitedUserID', true, 'invitation-pending');

-- Pending purchase held by the invited user
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'invitedPendingPurchaseID',
    2500,
    'USD',
    0,
    :'mainEventID',
    :'ticketTypeAID',
    now() + interval '15 minutes',
    'pending',
    'General admission',
    :'invitedUserID'
);

-- Existing completed purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'completedPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'mainEventID',
    :'ticketTypeAID',
    'completed',
    'General admission',
    :'completedUserID'
), (
    :'redeemedPurchaseID',
    2000,
    'USD',
    500,
    'TOTAL1',
    :'limitedDiscountID',
    :'mainEventID',
    :'ticketTypeAID',
    'completed',
    'General admission',
    :'redeemedUserID'
), (
    :'soldOutPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'soldOutEventID',
    :'soldOutTicketTypeID',
    'completed',
    'General admission',
    :'soldOutHolderUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create a pending checkout purchase
select lives_ok(
    $$select prepare_event_checkout_purchase(
        '79100000-0000-0000-0000-000000000001'::uuid,
        '79100000-0000-0000-0000-000000000003'::uuid,
        '79100000-0000-0000-0000-000000000006'::uuid,
        '79100000-0000-0000-0000-000000000023'::uuid,
        null,
        'stripe'
    )$$,
    'Should create a pending checkout purchase'
);

-- Should persist the pending checkout purchase for the selected ticket type
select results_eq(
    $$
        select
            amount_minor,
            event_ticket_type_id,
            status
        from event_purchase
        where event_id = '79100000-0000-0000-0000-000000000003'::uuid
        and user_id = '79100000-0000-0000-0000-000000000023'::uuid
        and status = 'pending'
    $$,
    $$ values (2500::bigint, '79100000-0000-0000-0000-000000000006'::uuid, 'pending'::text) $$,
    'Should persist the pending checkout purchase for the selected ticket type'
);

-- Should return the checkout route and recipient context alongside the purchase
select results_eq(
    $$
        with prepared_checkout as (
            select prepare_event_checkout_purchase(
                '79100000-0000-0000-0000-000000000001'::uuid,
                '79100000-0000-0000-0000-000000000003'::uuid,
                '79100000-0000-0000-0000-000000000006'::uuid,
                '79100000-0000-0000-0000-000000000023'::uuid,
                null,
                'stripe'
            ) as checkout
        )
        select
            checkout->>'community_name',
            checkout->>'event_slug',
            checkout->>'group_slug',
            checkout->>'group_slug_pretty',
            checkout->'recipient'->>'recipient_id'
        from prepared_checkout
    $$,
    $$ values ('prepare-community'::text, 'main-event'::text, 'prepare-group'::text, 'prepare-group-pretty'::text, 'acct_prepare'::text) $$,
    'Should return the checkout route and recipient context alongside the purchase'
);

-- Should reuse an equivalent pending purchase
select is(
    (
        select prepare_event_checkout_purchase(
            '79100000-0000-0000-0000-000000000001'::uuid,
            '79100000-0000-0000-0000-000000000003'::uuid,
            '79100000-0000-0000-0000-000000000006'::uuid,
            '79100000-0000-0000-0000-000000000023'::uuid,
            null,
            'stripe'
        )::jsonb->>'event_purchase_id'
    ),
    (
        select event_purchase_id::text
        from event_purchase
        where event_id = '79100000-0000-0000-0000-000000000003'::uuid
        and user_id = '79100000-0000-0000-0000-000000000023'::uuid
        and status = 'pending'
    ),
    'Should reuse an equivalent pending purchase'
);

-- Should replace a mismatched pending purchase
select lives_ok(
    $$
        select prepare_event_checkout_purchase(
            '79100000-0000-0000-0000-000000000001'::uuid,
            '79100000-0000-0000-0000-000000000003'::uuid,
            '79100000-0000-0000-0000-000000000007'::uuid,
            '79100000-0000-0000-0000-000000000023'::uuid,
            null,
            'stripe'
        )
    $$,
    'Should replace a mismatched pending purchase'
);

-- Should create the requested pending purchase and expire the previous one
select results_eq(
    $$
        select
            (
                select event_ticket_type_id::text
                from event_purchase
                where event_id = '79100000-0000-0000-0000-000000000003'::uuid
                and user_id = '79100000-0000-0000-0000-000000000023'::uuid
                and status = 'pending'
            ),
            (
                select count(*)::int
                from event_purchase
                where event_id = '79100000-0000-0000-0000-000000000003'::uuid
                and user_id = '79100000-0000-0000-0000-000000000023'::uuid
                and status = 'expired'
            ),
            (
                select hold_expires_at <= current_timestamp
                from event_purchase
                where event_id = '79100000-0000-0000-0000-000000000003'::uuid
                and user_id = '79100000-0000-0000-0000-000000000023'::uuid
                and status = 'expired'
            )
    $$,
    $$ values ('79100000-0000-0000-0000-000000000007'::text, 1::int, true) $$,
    'Should create the requested pending purchase and expire the previous one'
);

-- Should return an existing completed purchase as-is
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'mainEventID'::uuid,
        :'ticketTypeBID'::uuid,
        :'completedUserID'::uuid,
        null,
        'stripe'
    )::jsonb,
    jsonb_build_object(
        'amount_minor', 2500,
        'community_name', 'prepare-community',
        'currency_code', 'USD',
        'discount_amount_minor', 0,
        'event_id', :'mainEventID'::uuid,
        'event_slug', 'main-event',
        'event_purchase_id', :'completedPurchaseID'::uuid,
        'event_ticket_type_id', :'ticketTypeAID'::uuid,
        'group_slug', 'prepare-group',
        'group_slug_pretty', 'prepare-group-pretty',
        'recipient', jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_prepare'),
        'status', 'completed',
        'ticket_title', 'General admission'
    ),
    'Should return an existing completed purchase as-is'
);

-- Should apply a valid discount and decrement its availability
select lives_ok(
    $$
        select prepare_event_checkout_purchase(
            '79100000-0000-0000-0000-000000000001'::uuid,
            '79100000-0000-0000-0000-000000000003'::uuid,
            '79100000-0000-0000-0000-000000000006'::uuid,
            '79100000-0000-0000-0000-000000000028'::uuid,
            'freepass',
            'stripe'
        )
    $$,
    'Should apply a valid discount'
);

-- Should persist the discounted amount and decrement its availability
select results_eq(
    $$
        select
            (
                select amount_minor::text
                from event_purchase
                where event_id = '79100000-0000-0000-0000-000000000003'::uuid
                and user_id = '79100000-0000-0000-0000-000000000028'::uuid
                and status = 'pending'
            ),
            (
                select available::text
                from event_discount_code
                where event_discount_code_id = '79100000-0000-0000-0000-000000000016'::uuid
            )
    $$,
    $$ values ('0'::text, '1'::text) $$,
    'Should persist the discounted amount and decrement its availability'
);

-- Should reject discounted checkout amounts below minimums
select throws_ok(
    $$
        select prepare_event_checkout_purchase(
            '79100000-0000-0000-0000-000000000001'::uuid,
            '79100000-0000-0000-0000-000000000003'::uuid,
            '79100000-0000-0000-0000-000000000006'::uuid,
            '79100000-0000-0000-0000-000000000033'::uuid,
            'UNDERMIN',
            'stripe'
        )
    $$,
    'payment amount must be zero or at least Stripe minimum charge amount',
    'Should reject discounted checkout amounts below Stripe minimums'
);

-- Should require answers before preparing checkout for events with questions
select throws_ok(
    $$
        select prepare_event_checkout_purchase(
            '79100000-0000-0000-0000-000000000001'::uuid,
            '79100000-0000-0000-0000-000000000035'::uuid,
            '79100000-0000-0000-0000-000000000037'::uuid,
            '79100000-0000-0000-0000-000000000038'::uuid,
            null,
            'stripe'
        )
    $$,
    'questionnaire answers are required',
    'Should require answers before preparing checkout for events with questions'
);

-- Should prepare checkout when registration answers are provided
select lives_ok(
    $$
        select prepare_event_checkout_purchase(
            '79100000-0000-0000-0000-000000000001'::uuid,
            '79100000-0000-0000-0000-000000000035'::uuid,
            '79100000-0000-0000-0000-000000000037'::uuid,
            '79100000-0000-0000-0000-000000000038'::uuid,
            null,
            'stripe',
            '{"answers": [{"question_id": "79100000-0000-0000-0000-000000000101", "value": "Checkout answer"}]}'::jsonb
        )
    $$,
    'Should prepare checkout when registration answers are provided'
);

-- Should store checkout registration answers in a pending attendee row
select results_eq(
    $$
        select status, registration_answers
        from event_attendee
        where event_id = '79100000-0000-0000-0000-000000000035'::uuid
        and user_id = '79100000-0000-0000-0000-000000000038'::uuid
    $$,
    $$ values ('registration-questions-pending'::text, '{"answers": [{"question_id": "79100000-0000-0000-0000-000000000101", "value": "Checkout answer"}]}'::jsonb) $$,
    'Should store checkout registration answers in a pending attendee row'
);

-- Should reject reusing a pending purchase when an invitation is pending
select throws_ok(
    $$
        select prepare_event_checkout_purchase(
            '79100000-0000-0000-0000-000000000001'::uuid,
            '79100000-0000-0000-0000-000000000003'::uuid,
            '79100000-0000-0000-0000-000000000006'::uuid,
            '79100000-0000-0000-0000-000000000039'::uuid,
            null,
            'stripe'
        )
    $$,
    'user has a pending or rejected invitation for this event',
    'Should reject reusing a pending purchase when an invitation is pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
