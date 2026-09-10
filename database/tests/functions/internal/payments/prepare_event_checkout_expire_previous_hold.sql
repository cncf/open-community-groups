-- Tests expiring previous event checkout holds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79210000-0000-0000-0000-000000000001'
\set discountCodeID '79210000-0000-0000-0000-000000000002'
\set eventCategoryID '79210000-0000-0000-0000-000000000003'
\set eventID '79210000-0000-0000-0000-000000000004'
\set groupCategoryID '79210000-0000-0000-0000-000000000006'
\set groupID '79210000-0000-0000-0000-000000000007'
\set priceWindowID '79210000-0000-0000-0000-000000000008'
\set purchaseID '79210000-0000-0000-0000-000000000009'
\set ticketTypeID '79210000-0000-0000-0000-000000000005'
\set userID '79210000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_expire_replaced',
        'seller_display_name', 'Expire Replaced Fiscal Sponsor'
    )));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- Ticket type
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Price window
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));

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
    0,
    true,
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
);

-- Pending purchase
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
    :'purchaseID',
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
    :'userID'
);

-- Pending attendee row with registration answers created during checkout
insert into event_attendee (event_id, user_id, status)
values (
    :'eventID',
    :'userID',
    'registration-questions-pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should expire the replaced pending purchase
select lives_ok(
    format($$select prepare_event_checkout_expire_previous_hold(%L::uuid)$$, :'purchaseID'),
    'Should expire the replaced pending purchase'
);

-- Should restore the reserved discount inventory
select results_eq(
    format($$
        select
            (select hold_expires_at <= current_timestamp from event_purchase where event_purchase_id = %L::uuid),
            (select status from event_purchase where event_purchase_id = %L::uuid),
            (select available::text from event_discount_code where event_discount_code_id = %L::uuid),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
                and user_id = %L::uuid
            )
    $$, :'purchaseID', :'purchaseID', :'discountCodeID', :'eventID', :'userID'),
    $$ values (true, 'expired'::text, '1'::text, 0::int) $$,
    'Should restore the reserved discount inventory and release the registration hold'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
