-- Tests expiring purchases by checkout session.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79440000-0000-0000-0000-000000000001'
\set completedPurchaseID '79440000-0000-0000-0000-000000000002'
\set completedUserID '79440000-0000-0000-0000-000000000003'
\set discountCodeID '79440000-0000-0000-0000-000000000004'
\set eventCategoryID '79440000-0000-0000-0000-000000000005'
\set eventID '79440000-0000-0000-0000-000000000006'
\set eventTicketTypeID '79440000-0000-0000-0000-000000000007'
\set offerID '79440000-0000-0000-0000-000000000013'
\set groupCategoryID '79440000-0000-0000-0000-000000000008'
\set groupID '79440000-0000-0000-0000-000000000009'
\set pendingPurchaseID '79440000-0000-0000-0000-000000000010'
\set priceWindowID '79440000-0000-0000-0000-000000000011'
\set userID '79440000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'completedUserID');
select fx_user(:'userID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_test_group',
        'seller_display_name', 'Expire Checkout Fiscal Sponsor'
    )));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- Ticket type
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Price window
select fx_event_ticket_price_window(:'priceWindowID', :'eventTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Discount code
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    500,
    0,
    true,
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
);

-- Checkout-pending offer linked to the expiring purchase
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id,

    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    ticket_title
) values (
    :'offerID',
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    :'userID',

    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    'General admission'
);

-- Purchases
insert into event_purchase (
    admission_offer_id,
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    status,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot,

    final_platform_fee_amount_minor
) values (
    :'offerID',
    :'pendingPurchaseID',
    2000,
    'direct-charge',
    'acct_expire',
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    null,
    'cs_pending',
    'acct_expire',
    null,
    null,
    '{"connected_account_id":"acct_expire","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    null,
    null,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'userID',
    '{}'::jsonb,
    null
), (
    null,
    :'completedPurchaseID',
    2500,
    'direct-charge',
    'acct_expire',
    'USD',
    0,
    null,
    null,
    :'eventID',
    :'eventTicketTypeID',
    null,
    'stripe',
    'ch_completed',
    'cs_completed',
    'acct_expire',
    'pi_completed',
    2500,
    '{"connected_account_id":"acct_expire","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'completed',
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'completedUserID',
    '{}'::jsonb,
    0
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

-- Should expire the matching pending purchase
select lives_ok(
    $$select expire_event_purchase_for_checkout_session('stripe', 'acct_expire', 'cs_pending')$$,
    'Should expire the matching pending purchase'
);

-- Should mark the pending purchase as expired and release its registration hold
select results_eq(
    format($$
        select
            (
                select status
                from event_purchase
                where event_purchase_id = %L::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
                and user_id = %L::uuid
            ),
            (
                select status
                from admission_offer
                where admission_offer_id = %L::uuid
            )
    $$, :'pendingPurchaseID', :'eventID', :'userID', :'offerID'),
    $$ values ('expired'::text, 0::int, 'pending'::text) $$,
    'Should expire the purchase, release its registration hold, and preserve its offer'
);

-- Should restore discount availability when expiring the purchase
select is(
    (
        select available
        from event_discount_code
        where event_discount_code_id = :'discountCodeID'::uuid
    ),
    1,
    'Should restore discount availability when expiring the purchase'
);

-- Should ignore missing checkout sessions
select lives_ok(
    $$select expire_event_purchase_for_checkout_session('stripe', 'acct_expire', 'cs_missing')$$,
    'Should ignore missing checkout sessions'
);

-- Should leave completed purchases unchanged
select lives_ok(
    $$select expire_event_purchase_for_checkout_session('stripe', 'acct_expire', 'cs_completed')$$,
    'Should leave completed purchases unchanged'
);

-- Should preserve completed purchase state
select is(
    (
        select status
        from event_purchase
        where event_purchase_id = :'completedPurchaseID'::uuid
    ),
    'completed',
    'Should preserve completed purchase state'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
