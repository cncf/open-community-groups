-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79260000-0000-0000-0000-000000000001'
\set eventCategoryID '79260000-0000-0000-0000-000000000002'
\set mainEventID '79260000-0000-0000-0000-000000000003'
\set soldOutEventID '79260000-0000-0000-0000-000000000004'
\set inactiveEventID '79260000-0000-0000-0000-000000000005'
\set ticketTypeAID '79260000-0000-0000-0000-000000000006'
\set ticketTypeBID '79260000-0000-0000-0000-000000000007'
\set soldOutTicketTypeID '79260000-0000-0000-0000-000000000008'
\set inactiveTicketTypeID '79260000-0000-0000-0000-000000000009'
\set groupCategoryID '79260000-0000-0000-0000-000000000010'
\set groupID '79260000-0000-0000-0000-000000000011'
\set priceWindowAID '79260000-0000-0000-0000-000000000012'
\set priceWindowBID '79260000-0000-0000-0000-000000000013'
\set soldOutPriceWindowID '79260000-0000-0000-0000-000000000014'
\set inactivePriceWindowID '79260000-0000-0000-0000-000000000015'
\set freeDiscountID '79260000-0000-0000-0000-000000000016'
\set inactiveDiscountID '79260000-0000-0000-0000-000000000017'
\set limitedDiscountID '79260000-0000-0000-0000-000000000018'
\set percentageDiscountID '79260000-0000-0000-0000-000000000019'
\set redeemedPurchaseID '79260000-0000-0000-0000-000000000020'
\set soldOutPurchaseID '79260000-0000-0000-0000-000000000021'
\set attendeeUserID '79260000-0000-0000-0000-000000000022'
\set invalidDiscountUserID '79260000-0000-0000-0000-000000000023'
\set unavailableDiscountUserID '79260000-0000-0000-0000-000000000024'
\set exhaustedDiscountUserID '79260000-0000-0000-0000-000000000025'
\set fixedDiscountUserID '79260000-0000-0000-0000-000000000026'
\set percentageDiscountUserID '79260000-0000-0000-0000-000000000027'
\set soldOutUserID '79260000-0000-0000-0000-000000000028'
\set inactiveUserID '79260000-0000-0000-0000-000000000029'
\set redeemedUserID '79260000-0000-0000-0000-000000000030'
\set soldOutHolderUserID '79260000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'resolve-pricing-community', 'Resolve Pricing Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'attendeeUserID', 'hash-1', 'attendee@example.com', true, 'attendee'),
    (:'invalidDiscountUserID', 'hash-2', 'invalid@example.com', true, 'invalid-user'),
    (:'unavailableDiscountUserID', 'hash-3', 'unavailable@example.com', true, 'unavailable-user'),
    (:'exhaustedDiscountUserID', 'hash-4', 'exhausted@example.com', true, 'exhausted-user'),
    (:'fixedDiscountUserID', 'hash-5', 'fixed@example.com', true, 'fixed-user'),
    (:'percentageDiscountUserID', 'hash-6', 'percentage@example.com', true, 'percentage-user'),
    (:'soldOutUserID', 'hash-7', 'soldout@example.com', true, 'soldout-user'),
    (:'inactiveUserID', 'hash-8', 'inactive@example.com', true, 'inactive-user'),
    (:'redeemedUserID', 'hash-9', 'redeemed@example.com', true, 'redeemed-user'),
    (:'soldOutHolderUserID', 'hash-10', 'holder@example.com', true, 'holder-user');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, payment_recipient, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Resolve Pricing Group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_resolve_pricing'),
    'resolve-pricing-group'
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
    published_at
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
    now()
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
    now()
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
    now()
);

-- Ticket types
insert into event_ticket_type (event_ticket_type_id, active, event_id, "order", seats_total, title)
values
    (:'ticketTypeAID', true, :'mainEventID', 1, 10, 'General admission'),
    (:'ticketTypeBID', true, :'mainEventID', 2, 10, 'VIP'),
    (:'soldOutTicketTypeID', true, :'soldOutEventID', 1, 1, 'General admission'),
    (:'inactiveTicketTypeID', false, :'inactiveEventID', 1, 10, 'General admission');

-- Price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'priceWindowAID', 2500, :'ticketTypeAID'),
    (:'priceWindowBID', 4000, :'ticketTypeBID'),
    (:'soldOutPriceWindowID', 2500, :'soldOutTicketTypeID'),
    (:'inactivePriceWindowID', 2500, :'inactiveTicketTypeID');

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
    percentage,
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
    null,
    1,
    'Limited discount'
), (
    :'percentageDiscountID',
    true,
    null,
    4,
    true,
    'VIP25',
    :'mainEventID',
    'percentage',
    25,
    null,
    'VIP 25'
);

-- Existing attendee
insert into event_attendee (event_id, user_id)
values (:'mainEventID', :'attendeeUserID');

-- Existing purchases
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

-- Should reject attendees that already have a seat
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000006'::uuid,
        '79260000-0000-0000-0000-000000000022'::uuid,
        null
    )$$,
    'user is already attending this ticketed event',
    'Should reject attendees that already have a seat'
);

-- Should reject sold out ticket types
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000004'::uuid,
        '79260000-0000-0000-0000-000000000008'::uuid,
        '79260000-0000-0000-0000-000000000028'::uuid,
        null
    )$$,
    'ticket type is sold out',
    'Should reject sold out ticket types'
);

-- Should reject inactive ticket types
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000005'::uuid,
        '79260000-0000-0000-0000-000000000009'::uuid,
        '79260000-0000-0000-0000-000000000029'::uuid,
        null
    )$$,
    'ticket type is not active',
    'Should reject inactive ticket types'
);

-- Should reject unknown discount codes
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000006'::uuid,
        '79260000-0000-0000-0000-000000000023'::uuid,
        'missing'
    )$$,
    'discount code not found',
    'Should reject unknown discount codes'
);

-- Should reject unavailable discount codes
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000006'::uuid,
        '79260000-0000-0000-0000-000000000024'::uuid,
        'INACTIVE'
    )$$,
    'discount code is not available',
    'Should reject unavailable discount codes'
);

-- Should reject discounts whose total availability is exhausted
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000006'::uuid,
        '79260000-0000-0000-0000-000000000025'::uuid,
        'TOTAL1'
    )$$,
    'discount code is no longer available',
    'Should reject discounts whose total availability is exhausted'
);

-- Should compute pricing for a valid fixed-amount discount
select results_eq(
    $$
        select
            discount_amount_minor::text,
            event_discount_code_id::text,
            final_amount_minor::text,
            ticket_title
        from prepare_event_checkout_validate_and_resolve_pricing(
            '79260000-0000-0000-0000-000000000003'::uuid,
            '79260000-0000-0000-0000-000000000006'::uuid,
            '79260000-0000-0000-0000-000000000026'::uuid,
            'FREEPASS'
        )
    $$,
    $$ values (
        '2500'::text,
        '79260000-0000-0000-0000-000000000016'::text,
        '0'::text,
        'General admission'::text
    ) $$,
    'Should compute pricing for a valid fixed-amount discount'
);

-- Should compute pricing for a valid percentage discount
select results_eq(
    $$
        select
            discount_amount_minor::text,
            event_discount_code_id::text,
            final_amount_minor::text,
            ticket_title
        from prepare_event_checkout_validate_and_resolve_pricing(
            '79260000-0000-0000-0000-000000000003'::uuid,
            '79260000-0000-0000-0000-000000000007'::uuid,
            '79260000-0000-0000-0000-000000000027'::uuid,
            'VIP25'
        )
    $$,
    $$ values (
        '1000'::text,
        '79260000-0000-0000-0000-000000000019'::text,
        '3000'::text,
        'VIP'::text
    ) $$,
    'Should compute pricing for a valid percentage discount'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
