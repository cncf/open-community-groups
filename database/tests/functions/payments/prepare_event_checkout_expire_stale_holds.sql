-- Tests expiring stale event checkout holds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activePurchaseID '79220000-0000-0000-0000-000000000014'
\set communityID '79220000-0000-0000-0000-000000000001'
\set discountCodeID '79220000-0000-0000-0000-000000000002'
\set eventCategoryID '79220000-0000-0000-0000-000000000003'
\set eventID '79220000-0000-0000-0000-000000000004'
\set groupCategoryID '79220000-0000-0000-0000-000000000008'
\set groupID '79220000-0000-0000-0000-000000000009'
\set otherEventID '79220000-0000-0000-0000-000000000005'
\set otherEventPurchaseID '79220000-0000-0000-0000-000000000015'
\set otherPriceWindowID '79220000-0000-0000-0000-000000000011'
\set otherTicketTypeID '79220000-0000-0000-0000-000000000007'
\set priceWindowID '79220000-0000-0000-0000-000000000010'
\set stalePurchaseAID '79220000-0000-0000-0000-000000000012'
\set stalePurchaseBID '79220000-0000-0000-0000-000000000013'
\set ticketTypeID '79220000-0000-0000-0000-000000000006'
\set user1ID '79220000-0000-0000-0000-000000000016'
\set user2ID '79220000-0000-0000-0000-000000000017'
\set user3ID '79220000-0000-0000-0000-000000000018'
\set user4ID '79220000-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_user(:'user4ID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_expire_stale',
        'seller_display_name', 'Expire Stale Fiscal Sponsor'
    )));

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- Ticket types
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'otherTicketTypeID', :'otherEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Price windows
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'otherPriceWindowID', :'otherTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Discount code
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    true,
    500,
    1,
    true,
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
);

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
) values (
    :'stalePurchaseAID',
    0,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'ticketTypeID',
    now() - interval '10 minutes',
    'pending',
    'General admission',
    :'user1ID'
), (
    :'stalePurchaseBID',
    0,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'ticketTypeID',
    now() - interval '5 minutes',
    'pending',
    'General admission',
    :'user2ID'
), (
    :'activePurchaseID',
    0,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'ticketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user3ID'
), (
    :'otherEventPurchaseID',
    0,
    'USD',
    0,
    null,
    null,
    :'otherEventID',
    :'otherTicketTypeID',
    now() - interval '10 minutes',
    'pending',
    'General admission',
    :'user4ID'
);

-- Pending attendee rows with registration answers created during checkout
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'user1ID', 'registration-questions-pending'),
    (:'eventID', :'user2ID', 'registration-questions-pending'),
    (:'eventID', :'user3ID', 'registration-questions-pending'),
    (:'otherEventID', :'user4ID', 'registration-questions-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should expire stale pending holds for the selected event
select lives_ok(
    format($$select prepare_event_checkout_expire_stale_holds(%L::uuid)$$, :'eventID'),
    'Should expire stale pending holds for the selected event'
);

-- Should restore discount availability without touching active or other-event holds
select results_eq(
    format($$
        select
            (
                select count(*)::int
                from event_purchase
                where event_id = %L::uuid
                and status = 'expired'
            ),
            (
                select count(*)::int
                from event_purchase
                where event_id = %L::uuid
                and status = 'pending'
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = %L::uuid
            ),
            (
                select available::text
                from event_discount_code
                where event_discount_code_id = %L::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
            )
    $$, :'eventID', :'eventID', :'otherEventPurchaseID', :'discountCodeID', :'eventID', :'otherEventID'),
    $$ values (2::int, 1::int, 'pending'::text, '3'::text, 1::int, 1::int) $$,
    'Should restore discount availability and release only stale registration holds'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
