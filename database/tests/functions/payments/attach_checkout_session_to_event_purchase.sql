-- Tests attaching checkout sessions to event purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attachedPendingPurchaseID '79410000-0000-0000-0000-000000000001'
\set attachedUserID '79410000-0000-0000-0000-000000000002'
\set automaticTaxPurchaseID '79410000-0000-0000-0000-000000000014'
\set automaticTaxUserID '79410000-0000-0000-0000-000000000015'
\set communityID '79410000-0000-0000-0000-000000000003'
\set completedPurchaseID '79410000-0000-0000-0000-000000000004'
\set completedUserID '79410000-0000-0000-0000-000000000005'
\set eventCategoryID '79410000-0000-0000-0000-000000000006'
\set eventID '79410000-0000-0000-0000-000000000007'
\set eventTicketTypeID '79410000-0000-0000-0000-000000000008'
\set groupCategoryID '79410000-0000-0000-0000-000000000009'
\set groupID '79410000-0000-0000-0000-000000000010'
\set pendingPurchaseID '79410000-0000-0000-0000-000000000011'
\set priceWindowID '79410000-0000-0000-0000-000000000012'
\set userID '79410000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the ticketed event
select fx_community(:'communityID');

-- User holding the pending purchase that already has a checkout session
select fx_user(:'attachedUserID');

-- User holding the pending automatic-tax purchase
select fx_user(:'automaticTaxUserID');

-- User holding the completed purchase
select fx_user(:'completedUserID');

-- User holding the pending purchase awaiting a checkout session
select fx_user(:'userID');

-- Event category for the ticketed event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category for the organizing group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Cached tax location of the seller with a stale provider resource and venue
insert into payment_provider_tax_location (
    connected_seller_id,
    fingerprint,
    payment_provider_id,
    provider_tax_location_id,
    venue_snapshot
) values (
    'acct_attach',
    'fp_attach_location',
    'stripe',
    'loc_attach_stale',
    '{"name": "Stale Attach Venue"}'::jsonb
);

-- Group organizing the ticketed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_test_group',
        'seller_display_name', 'Checkout Session Fiscal Sponsor'
    )));

-- Event owning the purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- Ticket type of the purchases
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Price window of the ticket type
select fx_event_ticket_price_window(:'priceWindowID', :'eventTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Pending purchase awaiting a checkout session and completed purchase
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    :'pendingPurchaseID',
    2500,
    'direct-charge',
    'acct_attach',
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'stripe',
    'acct_attach',
    '{"connected_account_id":"acct_attach","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'userID',
    '{}'::jsonb
), (
    :'completedPurchaseID',
    0,
    'ocg-free',
    null,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    null,
    null,
    null,
    'completed',
    null,
    null,
    null,
    'General admission',
    :'completedUserID',
    null
);

-- Pending purchase that already has a checkout session
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
) values (
    :'attachedPendingPurchaseID',
    2500,
    'direct-charge',
    'acct_attach',
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'pending',
    'General admission',
    :'attachedUserID',

    'stripe',
    'cs_existing',
    'https://example.com/existing',
    'acct_attach',
    '{"connected_account_id":"acct_attach","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
);

-- Pending automatic-tax purchase whose venue refreshes the cached tax location
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_object_account_id,
    provider_tax_code,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    :'automaticTaxPurchaseID',
    2500,
    'direct-charge',
    'acct_attach',
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'stripe',
    'acct_attach',
    'txcd_50013001',
    '{"connected_account_id":"acct_attach","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'automatic',
    'professional-event-admission',
    'General admission',
    :'automaticTaxUserID',
    '{"name": "Current Attach Venue"}'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should link checkout session details to a pending purchase
select lives_ok(
    format($$
        select attach_checkout_session_to_event_purchase(
            %L::uuid,
            'stripe',
            'acct_attach',
            'cs_test_123',
            'https://example.com/checkout'
        )
    $$, :'pendingPurchaseID'),
    'Should link checkout session details to a pending purchase'
);

-- Should persist the provider checkout session details
select results_eq(
    format($$
        select
            payment_provider_id,
            provider_checkout_session_id,
            provider_checkout_url
        from event_purchase
        where event_purchase_id = %L::uuid
    $$, :'pendingPurchaseID'),
    $$
        values (
            'stripe'::text,
            'cs_test_123'::text,
            'https://example.com/checkout'::text
        )
    $$,
    'Should persist the provider checkout session details'
);

-- Should ignore non-pending purchases
select lives_ok(
    format($$
        select attach_checkout_session_to_event_purchase(
            %L::uuid,
            'stripe',
            'acct_attach',
            'cs_completed',
            'https://example.com/completed'
        )
    $$, :'completedPurchaseID'),
    'Should ignore non-pending purchases'
);

-- Should leave completed purchases unchanged
select results_eq(
    format($$
        select
            payment_provider_id,
            provider_checkout_session_id,
            provider_checkout_url
        from event_purchase
        where event_purchase_id = %L::uuid
    $$, :'completedPurchaseID'),
    $$ values (null::text, null::text, null::text) $$,
    'Should leave completed purchases unchanged'
);

-- Should ignore pending purchases that already have a checkout session
select lives_ok(
    format($$
        select attach_checkout_session_to_event_purchase(
            %L::uuid,
            'stripe',
            'acct_attach',
            'cs_replacement',
            'https://example.com/replacement'
        )
    $$, :'attachedPendingPurchaseID'),
    'Should ignore pending purchases that already have a checkout session'
);

-- Should keep the original checkout session details when already attached
select results_eq(
    format($$
        select
            payment_provider_id,
            provider_checkout_session_id,
            provider_checkout_url
        from event_purchase
        where event_purchase_id = %L::uuid
    $$, :'attachedPendingPurchaseID'),
    $$
        values (
            'stripe'::text,
            'cs_existing'::text,
            'https://example.com/existing'::text
        )
    $$,
    'Should keep the original checkout session details when already attached'
);

-- Should attach a checkout session with automatic-tax resources
select lives_ok(
    format($$
        select attach_checkout_session_to_event_purchase(
            %L::uuid,
            'stripe',
            'acct_attach',
            'cs_automatic_tax',
            'https://example.com/automatic-tax',
            'loc_attach_current',
            'fp_attach_location',
            'prod_attach_current',
            'fp_attach_product'
        )
    $$, :'automaticTaxPurchaseID'),
    'Should attach a checkout session with automatic-tax resources'
);

-- Should refresh the cached tax location and venue of an existing fingerprint
select results_eq(
    $$
        select provider_tax_location_id, venue_snapshot
        from payment_provider_tax_location
        where payment_provider_id = 'stripe'
        and connected_seller_id = 'acct_attach'
        and fingerprint = 'fp_attach_location'
    $$,
    $$ values ('loc_attach_current'::text, '{"name": "Current Attach Venue"}'::jsonb) $$,
    'Should refresh the cached tax location and venue of an existing fingerprint'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
