-- Tests preparing event checkout purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(51);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeUserID '79100000-0000-0000-0000-000000000022'
\set checkoutUserID '79100000-0000-0000-0000-000000000023'
\set closedWindowEventID '79100000-0000-0000-0000-000000000041'
\set closedWindowMatchingPurchaseID '79100000-0000-0000-0000-000000000042'
\set closedWindowMatchingUserID '79100000-0000-0000-0000-000000000043'
\set closedWindowMismatchedPurchaseID '79100000-0000-0000-0000-000000000044'
\set closedWindowMismatchedUserID '79100000-0000-0000-0000-000000000045'
\set closedWindowNewUserID '79100000-0000-0000-0000-000000000046'
\set closedWindowTicketTypeAID '79100000-0000-0000-0000-000000000047'
\set closedWindowTicketTypeBID '79100000-0000-0000-0000-000000000048'
\set closedWindowPriceWindowAID '79100000-0000-0000-0000-000000000049'
\set closedWindowPriceWindowBID '79100000-0000-0000-0000-00000000004a'
\set communityID '79100000-0000-0000-0000-000000000001'
\set completedPurchaseID '79100000-0000-0000-0000-000000000019'
\set completedUserID '79100000-0000-0000-0000-000000000024'
\set discountUserID '79100000-0000-0000-0000-000000000028'
\set eventCategoryID '79100000-0000-0000-0000-000000000002'
\set exhaustedDiscountUserID '79100000-0000-0000-0000-000000000027'
\set freeDiscountID '79100000-0000-0000-0000-000000000016'
\set freeEventID '79100000-0000-0000-0000-00000000004e'
\set freeGroupID '79100000-0000-0000-0000-00000000004d'
\set freePriceWindowID '79100000-0000-0000-0000-000000000050'
\set freeTicketTypeID '79100000-0000-0000-0000-00000000004f'
\set freeUserID '79100000-0000-0000-0000-000000000051'
\set groupCategoryID '79100000-0000-0000-0000-000000000010'
\set groupID '79100000-0000-0000-0000-000000000011'
\set inactiveDiscountID '79100000-0000-0000-0000-000000000017'
\set inactiveEventID '79100000-0000-0000-0000-000000000005'
\set inactivePriceWindowID '79100000-0000-0000-0000-000000000015'
\set inactiveTicketTypeID '79100000-0000-0000-0000-000000000009'
\set inactiveUserID '79100000-0000-0000-0000-000000000030'
\set ineffectiveDiscountID '79100000-0000-0000-0000-00000000006c'
\set ineffectiveDiscountOfferID '79100000-0000-0000-0000-00000000006d'
\set ineffectiveDiscountPriceWindowID '79100000-0000-0000-0000-00000000006e'
\set ineffectiveDiscountTicketTypeID '79100000-0000-0000-0000-00000000006f'
\set ineffectiveDiscountUserID '79100000-0000-0000-0000-000000000070'
\set invalidDiscountUserID '79100000-0000-0000-0000-000000000025'
\set invitedPendingPurchaseID '79100000-0000-0000-0000-000000000040'
\set invitedUserID '79100000-0000-0000-0000-000000000039'
\set offerDiscountID '79100000-0000-0000-0000-00000000005a'
\set offerDiscountUserID '79100000-0000-0000-0000-00000000005b'
\set offerFreeID '79100000-0000-0000-0000-00000000005c'
\set offerFreeUserID '79100000-0000-0000-0000-00000000005d'
\set offerPaidID '79100000-0000-0000-0000-00000000005e'
\set offerPaidUserID '79100000-0000-0000-0000-00000000005f'
\set offerPrivatePriceWindowID '79100000-0000-0000-0000-000000000060'
\set offerPrivateTicketTypeID '79100000-0000-0000-0000-000000000061'
\set offerWrongUserID '79100000-0000-0000-0000-000000000062'
\set paymentSetupUnavailableEventID '79100000-0000-0000-0000-000000000064'
\set paymentSetupUnavailablePriceWindowID '79100000-0000-0000-0000-000000000065'
\set paymentSetupUnavailableTicketTypeID '79100000-0000-0000-0000-000000000066'
\set paymentSetupUnavailableUserID '79100000-0000-0000-0000-000000000067'
\set platformFeeMaxUserID '79100000-0000-0000-0000-000000000072'
\set platformFeeUserID '79100000-0000-0000-0000-000000000071'
\set limitedDiscountID '79100000-0000-0000-0000-000000000018'
\set mainEventID '79100000-0000-0000-0000-000000000003'
\set priceUnavailableEventID '79100000-0000-0000-0000-000000000068'
\set priceUnavailablePriceWindowID '79100000-0000-0000-0000-000000000069'
\set priceUnavailableTicketTypeID '79100000-0000-0000-0000-00000000006a'
\set priceUnavailableUserID '79100000-0000-0000-0000-00000000006b'
\set priceWindowAID '79100000-0000-0000-0000-000000000012'
\set priceWindowBID '79100000-0000-0000-0000-000000000013'
\set queueCheckoutUserID '79100000-0000-0000-0000-000000000052'
\set queueDiscountID '79100000-0000-0000-0000-000000000063'
\set queueEventID '79100000-0000-0000-0000-000000000053'
\set queueExpiredPurchaseID '79100000-0000-0000-0000-000000000054'
\set queueHolderUserID '79100000-0000-0000-0000-000000000055'
\set queuePriceWindowID '79100000-0000-0000-0000-000000000056'
\set queueTicketTypeID '79100000-0000-0000-0000-000000000057'
\set queueUserID '79100000-0000-0000-0000-000000000058'
\set questionsEventID '79100000-0000-0000-0000-000000000035'
\set questionsPriceWindowID '79100000-0000-0000-0000-000000000036'
\set questionsTicketTypeID '79100000-0000-0000-0000-000000000037'
\set questionsUserID '79100000-0000-0000-0000-000000000038'
\set redeemedPurchaseID '79100000-0000-0000-0000-000000000020'
\set redeemedUserID '79100000-0000-0000-0000-000000000031'
\set registrationQuestionID '79100000-0000-0000-0000-000000000101'
\set soldOutEventID '79100000-0000-0000-0000-000000000004'
\set soldOutHolderUserID '79100000-0000-0000-0000-000000000032'
\set soldOutPendingPurchaseID '79100000-0000-0000-0000-00000000004b'
\set soldOutPendingUserID '79100000-0000-0000-0000-00000000004c'
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
    (:'closedWindowMatchingUserID', 'hash-15', 'closed-matching@example.com', true, 'closed-matching-user'),
    (:'closedWindowMismatchedUserID', 'hash-16', 'closed-mismatched@example.com', true, 'closed-mismatched-user'),
    (:'closedWindowNewUserID', 'hash-17', 'closed-new@example.com', true, 'closed-new-user'),
    (:'completedUserID', 'hash-3', 'completed@example.com', true, 'completed-user'),
    (:'ineffectiveDiscountUserID', 'hash-28', 'ineffective@example.com', true, 'ineffective-user'),
    (:'platformFeeMaxUserID', 'hash-30', 'platform-fee-max@example.com', true, 'platform-fee-max-user'),
    (:'platformFeeUserID', 'hash-29', 'platform-fee@example.com', true, 'platform-fee-user'),
    (:'invalidDiscountUserID', 'hash-4', 'invalid@example.com', true, 'invalid-user'),
    (:'unavailableDiscountUserID', 'hash-5', 'unavailable@example.com', true, 'unavailable-user'),
    (:'exhaustedDiscountUserID', 'hash-6', 'exhausted@example.com', true, 'exhausted-user'),
    (:'discountUserID', 'hash-7', 'discount@example.com', true, 'discount-user'),
    (:'freeUserID', 'hash-19', 'free@example.com', true, 'free-user'),
    (:'queueCheckoutUserID', 'hash-20', 'queue-checkout@example.com', true, 'queue-checkout-user'),
    (:'queueHolderUserID', 'hash-21', 'queue-holder@example.com', true, 'queue-holder-user'),
    (:'queueUserID', 'hash-22', 'queue-user@example.com', true, 'queue-user'),
    (:'soldOutUserID', 'hash-8', 'soldout@example.com', true, 'soldout-user'),
    (:'inactiveUserID', 'hash-9', 'inactive@example.com', true, 'inactive-user'),
    (:'redeemedUserID', 'hash-10', 'redeemed@example.com', true, 'redeemed-user'),
    (:'soldOutHolderUserID', 'hash-11', 'holder@example.com', true, 'holder-user'),
    (:'soldOutPendingUserID', 'hash-18', 'soldout-pending@example.com', true, 'soldout-pending-user'),
    (:'underMinimumUserID', 'hash-12', 'under-minimum@example.com', true, 'under-minimum-user'),
    (:'questionsUserID', 'hash-13', 'questions@example.com', true, 'questions-user'),
    (:'invitedUserID', 'hash-14', 'invited@example.com', true, 'invited-user'),
    (:'offerDiscountUserID', 'hash-23', 'offer-discount@example.com', true, 'offer-discount-user'),
    (:'offerFreeUserID', 'hash-24', 'offer-free@example.com', true, 'offer-free-user'),
    (:'offerPaidUserID', 'hash-25', 'offer-paid@example.com', true, 'offer-paid-user'),
    (:'offerWrongUserID', 'hash-26', 'offer-wrong@example.com', true, 'offer-wrong-user'),
    (:'paymentSetupUnavailableUserID', 'hash-27', 'payment-setup-unavailable@example.com', true, 'payment-setup-unavailable-user'),
    (:'priceUnavailableUserID', 'hash-28', 'price-unavailable@example.com', true, 'price-unavailable-user');

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
values
    (
        :'freeGroupID',
        :'communityID',
        :'groupCategoryID',
        'Free Group',
        'free-group',
        null,
        null
    ),
    (
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
    :'freeEventID',
    :'eventCategoryID',
    'in-person',
    :'freeGroupID',
    'Free Event',
    'free-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    null,
    true,
    now(),
    '[]'::jsonb
), (
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
    :'queueEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Queue Priority Event',
    'queue-priority-event',
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

-- Closed registration window event that is still active
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
    ends_at,
    payment_currency_code,
    published,
    published_at,
    registration_starts_at,
    registration_questions
) values (
    :'closedWindowEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Closed Window Event',
    'closed-window-event',
    'Test event',
    'UTC',
    now() - interval '30 minutes',
    now() + interval '90 minutes',
    'USD',
    true,
    now(),
    now() - interval '2 hours',
    '[]'::jsonb
);

-- Paid event without payment setup used by the readiness conflict
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
    :'paymentSetupUnavailableEventID',
    :'eventCategoryID',
    'in-person',
    :'freeGroupID',
    'Payment Setup Unavailable Event',
    'payment-setup-unavailable-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    'USD',
    true,
    now(),
    '[]'::jsonb
);

-- Event with a lapsed ticket price used by the price availability conflict
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
    :'priceUnavailableEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Price Unavailable Event',
    'price-unavailable-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    'USD',
    true,
    now(),
    '[]'::jsonb
);

-- Ticket types
insert into event_ticket_type (
    active,
    availability,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
)
values
    (true, 'public', :'freeEventID', :'freeTicketTypeID', 1, 10, 'Free admission'),
    (true, 'public', :'mainEventID', :'ticketTypeAID', 1, 10, 'General admission'),
    (true, 'public', :'mainEventID', :'ticketTypeBID', 2, 10, 'VIP'),
    (
        true,
        'public',
        :'mainEventID',
        :'ineffectiveDiscountTicketTypeID',
        4,
        10,
        'Minor-unit admission'
    ),
    (true, 'public', :'closedWindowEventID', :'closedWindowTicketTypeAID', 1, 10, 'General admission'),
    (true, 'public', :'closedWindowEventID', :'closedWindowTicketTypeBID', 2, 10, 'VIP'),
    (true, 'public', :'queueEventID', :'queueTicketTypeID', 1, 1, 'Queue admission'),
    (true, 'public', :'soldOutEventID', :'soldOutTicketTypeID', 1, 1, 'General admission'),
    (false, 'public', :'inactiveEventID', :'inactiveTicketTypeID', 1, 10, 'General admission'),
    (
        true,
        'invitation_only',
        :'mainEventID',
        :'offerPrivateTicketTypeID',
        3,
        10,
        'Invitation admission'
    ),
    (true, 'public', :'questionsEventID', :'questionsTicketTypeID', 1, 10, 'General admission');

-- Ticket types dedicated to mutable configuration conflict scenarios
insert into event_ticket_type (
    active,
    availability,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values
    (
        true,
        'public',
        :'paymentSetupUnavailableEventID',
        :'paymentSetupUnavailableTicketTypeID',
        1,
        10,
        'Payment setup admission'
    ),
    (
        true,
        'public',
        :'priceUnavailableEventID',
        :'priceUnavailableTicketTypeID',
        1,
        10,
        'Price unavailable admission'
    );

-- Price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'freePriceWindowID', 0, :'freeTicketTypeID'),
    (:'ineffectiveDiscountPriceWindowID', 1, :'ineffectiveDiscountTicketTypeID'),
    (:'priceWindowAID', 2500, :'ticketTypeAID'),
    (:'priceWindowBID', 4000, :'ticketTypeBID'),
    (:'closedWindowPriceWindowAID', 2500, :'closedWindowTicketTypeAID'),
    (:'closedWindowPriceWindowBID', 4000, :'closedWindowTicketTypeBID'),
    (:'queuePriceWindowID', 2500, :'queueTicketTypeID'),
    (:'soldOutPriceWindowID', 2500, :'soldOutTicketTypeID'),
    (:'inactivePriceWindowID', 2500, :'inactiveTicketTypeID'),
    (:'offerPrivatePriceWindowID', 3000, :'offerPrivateTicketTypeID'),
    (:'questionsPriceWindowID', 2500, :'questionsTicketTypeID');

-- Current paid price window used by the payment readiness conflict
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'paymentSetupUnavailablePriceWindowID',
    2500,
    :'paymentSetupUnavailableTicketTypeID'
);

-- Lapsed price window used by the price availability conflict
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id,
    ends_at,
    starts_at
) values (
    :'priceUnavailablePriceWindowID',
    2500,
    :'priceUnavailableTicketTypeID',
    current_timestamp - interval '1 minute',
    current_timestamp - interval '2 days'
);

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
    4,
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
    :'queueDiscountID',
    true,
    2500,
    1,
    true,
    'QUEUEFREE',
    :'queueEventID',
    'fixed_amount',
    null,
    'Queue free pass'
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

-- Percentage discount too small to reduce the minor-unit price
insert into event_discount_code (
    event_discount_code_id,
    active,
    code,
    event_id,
    kind,
    title,

    available,
    available_override_active,
    percentage
) values (
    :'ineffectiveDiscountID',
    true,
    'TINY25',
    :'mainEventID',
    'percentage',
    'Tiny percentage',

    5,
    true,
    25
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

-- Pending purchases that should remain reusable after registration or availability closes
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
    :'closedWindowMatchingPurchaseID',
    2500,
    'USD',
    0,
    :'closedWindowEventID',
    :'closedWindowTicketTypeAID',
    now() + interval '15 minutes',
    'pending',
    'General admission',
    :'closedWindowMatchingUserID'
), (
    :'closedWindowMismatchedPurchaseID',
    2500,
    'USD',
    0,
    :'closedWindowEventID',
    :'closedWindowTicketTypeAID',
    now() + interval '15 minutes',
    'pending',
    'General admission',
    :'closedWindowMismatchedUserID'
), (
    :'queueExpiredPurchaseID',
    2500,
    'USD',
    0,
    :'queueEventID',
    :'queueTicketTypeID',
    now() - interval '1 minute',
    'pending',
    'Queue admission',
    :'queueHolderUserID'
), (
    :'soldOutPendingPurchaseID',
    2500,
    'USD',
    0,
    :'soldOutEventID',
    :'soldOutTicketTypeID',
    now() + interval '15 minutes',
    'pending',
    'General admission',
    :'soldOutPendingUserID'
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

-- FIFO queue that must take released capacity before direct checkout
insert into event_waitlist (
    created_at,
    event_id,
    event_ticket_type_id,
    user_id
) values (
    current_timestamp,
    :'queueEventID',
    :'queueTicketTypeID',
    :'queueUserID'
);

-- Owned offers for paid, discounted-to-zero, and intrinsic-free claims
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values
    (
        :'ineffectiveDiscountOfferID',
        :'mainEventID',
        :'ineffectiveDiscountTicketTypeID',
        now() + interval '1 day',
        'approval',
        'pending',
        :'ineffectiveDiscountUserID'
    ),
    (
        :'offerDiscountID',
        :'mainEventID',
        :'ticketTypeAID',
        now() + interval '1 day',
        'approval',
        'pending',
        :'offerDiscountUserID'
    ),
    (
        :'offerFreeID',
        :'freeEventID',
        :'freeTicketTypeID',
        now() + interval '1 day',
        'organizer_invitation',
        'pending',
        :'offerFreeUserID'
    ),
    (
        :'offerPaidID',
        :'mainEventID',
        :'offerPrivateTicketTypeID',
        now() + interval '1 day',
        'organizer_invitation',
        'pending',
        :'offerPaidUserID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should prepare intrinsic zero-price checkout without provider or recipient setup
select results_eq(
    $$
        with prepared_checkout as (
            select prepare_event_checkout_purchase(
                '79100000-0000-0000-0000-000000000001'::uuid,
                '79100000-0000-0000-0000-00000000004e'::uuid,
                '79100000-0000-0000-0000-00000000004f'::uuid,
                '79100000-0000-0000-0000-000000000051'::uuid,
                null,
                null,
                null,
                null,
                250
            ) as checkout
        )
        select
            checkout->>'amount_minor',
            checkout ? 'currency_code',
            checkout->>'platform_fee_amount_minor',
            checkout->'recipient'
        from prepared_checkout
    $$,
    $$ values ('0'::text, false, '0'::text, 'null'::jsonb) $$,
    'Should prepare intrinsic zero-price checkout without payment setup'
);

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
            platform_fee_amount_minor,
            status
        from event_purchase
        where event_id = '79100000-0000-0000-0000-000000000003'::uuid
        and user_id = '79100000-0000-0000-0000-000000000023'::uuid
        and status = 'pending'
    $$,
    $$
        values (
            2500::bigint,
            '79100000-0000-0000-0000-000000000006'::uuid,
            0::bigint,
            'pending'::text
        )
    $$,
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
        'platform_fee_amount_minor', 0,
        'recipient', jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_prepare'),
        'status', 'completed',
        'ticket_title', 'General admission'
    ),
    'Should return an existing completed purchase as-is'
);

-- Should snapshot the platform fee from the final amount rounding down
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'mainEventID'::uuid,
            :'ticketTypeAID'::uuid,
            :'platformFeeUserID'::uuid,
            null,
            'stripe',
            null,
            null,
            250
        )::jsonb->>'platform_fee_amount_minor'
    ),
    '62',
    'Should snapshot the platform fee from the final amount rounding down'
);

-- Should persist the platform fee snapshot on the pending purchase
select results_eq(
    format(
        $$
        select platform_fee_amount_minor
        from event_purchase
        where event_id = %L::uuid
        and user_id = %L::uuid
        $$,
        :'mainEventID',
        :'platformFeeUserID'
    ),
    $$ values (62::bigint) $$,
    'Should persist the platform fee snapshot on the pending purchase'
);

-- Should retain the original platform fee snapshot when reusing a purchase
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'mainEventID'::uuid,
            :'ticketTypeAID'::uuid,
            :'platformFeeUserID'::uuid,
            null,
            'stripe',
            null,
            null,
            500
        )::jsonb->>'platform_fee_amount_minor'
    ),
    '62',
    'Should retain the original platform fee snapshot when reusing a purchase'
);

-- Should allow a platform fee that consumes the full amount
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'mainEventID'::uuid,
            :'ticketTypeAID'::uuid,
            :'platformFeeMaxUserID'::uuid,
            null,
            'stripe',
            null,
            null,
            10000
        )::jsonb->>'platform_fee_amount_minor'
    ),
    '2500',
    'Should allow a platform fee that consumes the full amount'
);

-- Should reject platform fee basis points above the maximum
select throws_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            null,
            10001
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'platformFeeUserID'
    ),
    'platform fee basis points must be between 0 and 10000',
    'Should reject platform fee basis points above the maximum'
);

-- Should reject negative platform fee basis points
select throws_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            null,
            -1
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'platformFeeUserID'
    ),
    'platform fee basis points must be between 0 and 10000',
    'Should reject negative platform fee basis points'
);

-- Should reuse an equivalent pending purchase after registration closes
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'closedWindowEventID'::uuid,
            :'closedWindowTicketTypeAID'::uuid,
            :'closedWindowMatchingUserID'::uuid,
            null,
            'stripe'
        )::jsonb->>'event_purchase_id'
    ),
    :'closedWindowMatchingPurchaseID',
    'Should reuse an equivalent pending purchase after registration closes'
);

-- Should reject replacing a pending purchase after registration closes
select throws_ok(
    format($$select prepare_event_checkout_purchase(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        'stripe'
    )$$,
        :'communityID',
        :'closedWindowEventID',
        :'closedWindowTicketTypeBID',
        :'closedWindowMismatchedUserID'
    ),
    'event registration is not open',
    'Should reject replacing a pending purchase after registration closes'
);

-- Should keep rejected replacement holds active
select results_eq(
    $$
        select
            status,
            hold_expires_at > current_timestamp
        from event_purchase
        where event_purchase_id = '79100000-0000-0000-0000-000000000044'::uuid
    $$,
    $$ values ('pending'::text, true) $$,
    'Should keep rejected replacement holds active'
);

-- Should reject creating a checkout purchase after registration closes
select throws_ok(
    format($$select prepare_event_checkout_purchase(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        'stripe'
    )$$,
        :'communityID',
        :'closedWindowEventID',
        :'closedWindowTicketTypeAID',
        :'closedWindowNewUserID'
    ),
    'event registration is not open',
    'Should reject creating a checkout purchase after registration closes'
);

-- Should reuse an equivalent pending purchase when the ticket type is sold out
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'soldOutEventID'::uuid,
            :'soldOutTicketTypeID'::uuid,
            :'soldOutPendingUserID'::uuid,
            null,
            'stripe'
        )::jsonb->>'event_purchase_id'
    ),
    :'soldOutPendingPurchaseID',
    'Should reuse an equivalent pending purchase when the ticket type is sold out'
);

-- Should preserve a payment-blocked queue head over discounted direct checkout
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'queueEventID'::uuid,
        :'queueTicketTypeID'::uuid,
        :'queueCheckoutUserID'::uuid,
        'QUEUEFREE',
        null
    ),
    '{"conflict":"ticket-type-sold-out"}'::jsonb,
    'Should preserve a payment-blocked queue head over discounted direct checkout'
);

-- Should preserve FIFO queue priority over direct checkout
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'queueEventID'::uuid,
        :'queueTicketTypeID'::uuid,
        :'queueCheckoutUserID'::uuid,
        null,
        'stripe'
    ),
    '{"conflict":"ticket-type-sold-out"}'::jsonb,
    'Should preserve FIFO queue priority over direct checkout'
);

-- Should commit queue promotion and stale-hold expiry with the typed conflict
select is(
    (
        select jsonb_build_object(
            'offer_status', (
                select status
                from admission_offer
                where event_id = :'queueEventID'::uuid
                and user_id = :'queueUserID'::uuid
            ),
            'purchase_status', (
                select status
                from event_purchase
                where event_purchase_id = :'queueExpiredPurchaseID'::uuid
            ),
            'waitlist_count', (
                select count(*)
                from event_waitlist
                where event_id = :'queueEventID'::uuid
            )
        )
    ),
    '{"offer_status":"pending","purchase_status":"expired","waitlist_count":0}'::jsonb,
    'Should persist reconciliation before rejecting direct checkout'
);

-- Should reject attempts to claim another user's offer
select is(
    prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'mainEventID'::uuid,
            :'offerPrivateTicketTypeID'::uuid,
            :'offerWrongUserID'::uuid,
            null,
            'stripe',
            null,
            :'offerPaidID'::uuid
    ),
    '{"conflict":"admission-offer-unavailable"}'::jsonb,
    'Should reject claiming an offer owned by another user'
);

-- Should prepare a paid checkout for an invitation-only offer
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'freepass',
            'stripe',
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'offerPrivateTicketTypeID',
        :'offerPaidUserID',
        :'offerPaidID'
    ),
    'Should prepare paid checkout for an invitation-only offer'
);

-- Should require the offer checkout path while its linked hold remains active
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'mainEventID'::uuid,
        :'offerPrivateTicketTypeID'::uuid,
        :'offerPaidUserID'::uuid,
        null,
        'stripe'
    ),
    '{"conflict":"admission-offer-required"}'::jsonb,
    'Should require the offer checkout path while its linked hold remains active'
);

select results_eq(
    format(
        $$
        select
            ao.amount_minor,
            ao.currency_code,
            ao.discount_amount_minor,
            ao.discount_code,
            ao.status,
            ep.admission_offer_id,
            ep.amount_minor,
            ep.discount_code,
            ep.status
        from admission_offer ao
        join event_purchase ep using (admission_offer_id)
        where ao.admission_offer_id = %L::uuid
        $$,
        :'offerPaidID'
    ),
    format(
        $$
        values (
            500::bigint,
            'USD'::text,
            2500::bigint,
            'FREEPASS'::text,
            'checkout_pending'::text,
            %L::uuid,
            500::bigint,
            'FREEPASS'::text,
            'pending'::text
        )
        $$,
        :'offerPaidID'
    ),
    'Should snapshot and link the paid offer checkout'
);

select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'mainEventID'::uuid,
            :'offerPrivateTicketTypeID'::uuid,
            :'offerPaidUserID'::uuid,
            null,
            'stripe',
            null,
            :'offerPaidID'::uuid
        )->>'event_purchase_id'
    ),
    (
        select event_purchase_id::text
        from event_purchase
        where admission_offer_id = :'offerPaidID'::uuid
    ),
    'Should reuse the pending checkout for the same offer'
);

-- Should retain the first claim snapshot across canceled checkout retries
select lives_ok(
    format(
        $$ select cancel_event_checkout(%L, %L, %L, 'stripe') $$,
        :'communityID',
        :'mainEventID',
        :'offerPaidUserID'
    ),
    'Should cancel the first offer-linked checkout'
);

select lives_ok(
    format(
        $$
        select sync_event_ticket_types(
            %L::uuid,
            '[
                {
                    "active": true,
                    "availability": "public",
                    "event_ticket_type_id": "%s",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "%s"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General admission"
                },
                {
                    "active": true,
                    "availability": "public",
                    "event_ticket_type_id": "%s",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 4000,
                            "event_ticket_price_window_id": "%s"
                        }
                    ],
                    "seats_total": 10,
                    "title": "VIP"
                },
                {
                    "active": true,
                    "availability": "invitation_only",
                    "event_ticket_type_id": "%s",
                    "order": 3,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "%s"
                        }
                    ],
                    "seats_total": 10,
                    "title": "Invitation admission"
                },
                {
                    "active": true,
                    "availability": "public",
                    "event_ticket_type_id": "%s",
                    "order": 4,
                    "price_windows": [
                        {
                            "amount_minor": 1,
                            "event_ticket_price_window_id": "%s"
                        }
                    ],
                    "seats_total": 10,
                    "title": "Minor-unit admission"
                }
            ]'::jsonb
        )
        $$,
        :'mainEventID',
        :'ticketTypeAID',
        :'priceWindowAID',
        :'ticketTypeBID',
        :'priceWindowBID',
        :'offerPrivateTicketTypeID',
        :'offerPrivatePriceWindowID',
        :'ineffectiveDiscountTicketTypeID',
        :'ineffectiveDiscountPriceWindowID'
    ),
    'Should change the tier price after the first offer claim'
);

select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'offerPrivateTicketTypeID',
        :'offerPaidUserID',
        :'offerPaidID'
    ),
    'Should retry checkout through the same offer'
);

select results_eq(
    format(
        $$
        select
            ao.amount_minor,
            current_price.amount_minor,
            count(*) filter (where ep.status = 'expired')::int,
            count(*) filter (where ep.status = 'pending')::int,
            min(ep.amount_minor),
            max(ep.amount_minor)
        from admission_offer ao
        join event_purchase ep using (admission_offer_id)
        join event_ticket_price_window current_price
            on current_price.event_ticket_type_id = ao.event_ticket_type_id
        where ao.admission_offer_id = %L::uuid
        group by ao.amount_minor, current_price.amount_minor
        $$,
        :'offerPaidID'
    ),
    $$ values (500::bigint, 5000::bigint, 1, 1, 500::bigint, 500::bigint) $$,
    'Should copy the immutable first claim snapshot into every retry purchase'
);

select throws_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'total1',
            'stripe',
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'offerPrivateTicketTypeID',
        :'offerPaidUserID',
        :'offerPaidID'
    ),
    'P0001',
    'admission offer price selection cannot be changed',
    'Should reject changing the offer discount selection on retry'
);

-- Should reject offer discounts below one minor unit
select throws_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'tiny25',
            'stripe',
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'ineffectiveDiscountTicketTypeID',
        :'ineffectiveDiscountUserID',
        :'ineffectiveDiscountOfferID'
    ),
    'P0001',
    'discount code does not reduce ticket price',
    'Should reject offer discounts below one minor unit'
);

select results_eq(
    format(
        $$
            select
                ao.amount_minor is null,
                ao.status,
                (
                    select count(*)::int
                    from event_purchase ep
                    where ep.admission_offer_id = ao.admission_offer_id
                ),
                (
                    select available
                    from event_discount_code edc
                    where edc.event_discount_code_id = %L::uuid
                )
            from admission_offer ao
            where ao.admission_offer_id = %L::uuid
        $$,
        :'ineffectiveDiscountID',
        :'ineffectiveDiscountOfferID'
    ),
    $$ values (true, 'pending'::text, 0::int, 5::int) $$,
    'Should leave rejected offer discount state unchanged'
);

-- Should prepare and snapshot a discounted-to-zero offer claim
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'freepass',
            null,
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'offerDiscountUserID',
        :'offerDiscountID'
    ),
    'Should prepare a discounted-to-zero offer claim'
);

select results_eq(
    format(
        $$
        select
            ao.amount_minor,
            ao.currency_code,
            ao.discount_amount_minor,
            ao.discount_code,
            ep.amount_minor,
            ep.currency_code
        from admission_offer ao
        join event_purchase ep using (admission_offer_id)
        where ao.admission_offer_id = %L::uuid
        $$,
        :'offerDiscountID'
    ),
    $$ values (0::bigint, 'USD'::text, 2500::bigint, 'FREEPASS'::text, 0::bigint, 'USD'::text) $$,
    'Should retain discounted-to-zero offer price snapshots'
);

-- Should cancel the discounted-to-zero offer checkout before retry
select lives_ok(
    format(
        $$ select cancel_event_checkout(%L, %L, %L, null) $$,
        :'communityID',
        :'mainEventID',
        :'offerDiscountUserID'
    ),
    'Should cancel the discounted-to-zero offer checkout'
);

-- Should retry the discounted-to-zero offer without resubmitting its code
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            null,
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'offerDiscountUserID',
        :'offerDiscountID'
    ),
    'Should retry the discounted-to-zero offer without resubmitting its code'
);

-- Should reuse the discounted-to-zero offer snapshot for its retry purchase
select results_eq(
    format(
        $$
        select
            count(*) filter (where ep.status = 'expired')::int,
            count(*) filter (where ep.status = 'pending')::int,
            bool_and(ep.discount_code = 'FREEPASS'),
            min(ep.amount_minor),
            max(ep.amount_minor)
        from event_purchase ep
        where ep.admission_offer_id = %L::uuid
        $$,
        :'offerDiscountID'
    ),
    $$ values (1, 1, true, 0::bigint, 0::bigint) $$,
    'Should reuse the discounted-to-zero offer snapshot for its retry purchase'
);

-- Should prepare an intrinsic-free offer without payment configuration
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            null,
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'freeEventID',
        :'freeTicketTypeID',
        :'offerFreeUserID',
        :'offerFreeID'
    ),
    'Should prepare an intrinsic-free offer claim'
);

select results_eq(
    format(
        $$
        select
            ao.amount_minor,
            ao.currency_code,
            ao.status,
            ep.amount_minor,
            ep.currency_code
        from admission_offer ao
        join event_purchase ep using (admission_offer_id)
        where ao.admission_offer_id = %L::uuid
        $$,
        :'offerFreeID'
    ),
    $$ values (0::bigint, null::text, 'checkout_pending'::text, 0::bigint, null::text) $$,
    'Should retain intrinsic-free offer price snapshots'
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
            null
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
                select currency_code
                from event_purchase
                where event_id = '79100000-0000-0000-0000-000000000003'::uuid
                and user_id = '79100000-0000-0000-0000-000000000028'::uuid
                and status = 'pending'
            ),
            (
                select discount_amount_minor::text
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
    $$ values ('0'::text, 'USD'::text, '2500'::text, '1'::text) $$,
    'Should persist discounted-to-zero snapshots and decrement availability'
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

-- Should return a typed conflict for an inactive ticket type
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'inactiveEventID'::uuid,
        :'inactiveTicketTypeID'::uuid,
        :'inactiveUserID'::uuid,
        null,
        'stripe'
    ),
    '{"conflict":"ticket-type-inactive"}'::jsonb,
    'Should return a typed conflict for an inactive ticket type'
);

-- Should return a typed conflict when a ticket type has no current price
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'priceUnavailableEventID'::uuid,
        :'priceUnavailableTicketTypeID'::uuid,
        :'priceUnavailableUserID'::uuid,
        null,
        'stripe'
    ),
    '{"conflict":"ticket-type-price-unavailable"}'::jsonb,
    'Should return a typed conflict when a ticket type has no current price'
);

-- Should return a typed conflict when paid checkout setup is unavailable
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'paymentSetupUnavailableEventID'::uuid,
        :'paymentSetupUnavailableTicketTypeID'::uuid,
        :'paymentSetupUnavailableUserID'::uuid,
        null,
        null
    ),
    '{"conflict":"payment-setup-unavailable"}'::jsonb,
    'Should return a typed conflict when paid checkout setup is unavailable'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
