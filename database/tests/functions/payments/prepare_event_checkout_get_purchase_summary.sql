-- Tests retrieving prepared event checkout purchase summaries.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79240000-0000-0000-0000-000000000001'
\set eventCategoryID '79240000-0000-0000-0000-000000000002'
\set eventID '79240000-0000-0000-0000-000000000003'
\set groupCategoryID '79240000-0000-0000-0000-000000000005'
\set groupID '79240000-0000-0000-0000-000000000006'
\set priceWindowID '79240000-0000-0000-0000-000000000007'
\set purchaseID '79240000-0000-0000-0000-000000000008'
\set purchaseWithProviderFieldsID '79240000-0000-0000-0000-000000000010'
\set ticketTypeID '79240000-0000-0000-0000-000000000004'
\set userID '79240000-0000-0000-0000-000000000009'

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
        'recipient_id', 'acct_get_summary',
        'seller_display_name', 'Purchase Summary Fiscal Sponsor'
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

-- Purchase
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    completed_at,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    manual_tax_rate_ids,
    payment_provider_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    provider_charge_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    refunded_at,
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
    :'purchaseID',
    2500,
    'direct-charge',
    null,
    'acct_get_summary',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeID',
    '2030-01-01 10:00:00+00'::timestamptz,
    array['txr_state', 'txr_local']::text[],
    null,
    0,
    0,
    null,
    null,
    null,
    'acct_get_summary',
    null,
    null,
    null,
    '{"connected_account_id":"acct_get_summary","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    null,
    null,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'userID',
    '{"address":"1 Main St","city":"Portland","country_code":"US","name":"Venue","state_code":"OR","state_name":"Oregon","zip_code":"97201"}'::jsonb,
    null
), (
    :'purchaseWithProviderFieldsID',
    2000,
    'direct-charge',
    '2030-01-02 10:15:00+00'::timestamptz,
    'acct_get_summary',
    'USD',
    500,
    'SAVE20',
    :'eventID',
    :'ticketTypeID',
    '2030-01-01 12:30:00+00'::timestamptz,
    array['txr_state']::text[],
    'stripe',
    1000,
    200,
    'ch_get_summary',
    'cs_get_summary',
    'https://example.com/checkout/cs_get_summary',
    'acct_get_summary',
    'pi_get_summary',
    2000,
    '2030-01-03 08:45:00+00'::timestamptz,
    '{"connected_account_id":"acct_get_summary","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'refunded',
    2000,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'userID',
    '{"address":"1 Main St","city":"Portland","country_code":"US","name":"Venue","state_code":"OR","state_name":"Oregon","zip_code":"97201"}'::jsonb,
    200
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the attendee-facing checkout summary without null provider fields
select is(
    prepare_event_checkout_get_purchase_summary(:'purchaseID'::uuid),
    jsonb_build_object(
        'amount_minor', 2500,
        'charge_model', 'direct-charge',
        'currency_code', 'USD',
        'discount_amount_minor', 0,
        'event_purchase_id', :'purchaseID'::uuid,
        'event_ticket_type_id', :'ticketTypeID'::uuid,
        'hold_expires_at', 1893492000,
        'manual_tax_rate_ids', jsonb_build_array('txr_state', 'txr_local'),
        'provisional_platform_fee_amount_minor', 0,
        'provider_object_account_id', 'acct_get_summary',
        'seller', '{"connected_account_id":"acct_get_summary","display_name":"Sponsor","provider":"stripe"}'::jsonb,
        'status', 'pending',
        'tax_behavior', 'inclusive',
        'tax_calculation_mode', 'manual',
        'ticket_title', 'General admission',
        'venue', '{"address":"1 Main St","city":"Portland","country_code":"US","name":"Venue","state_code":"OR","state_name":"Oregon","zip_code":"97201"}'::jsonb
    ),
    'Should return the attendee-facing checkout summary without null provider fields'
);

-- Should return all checkout summary fields when they are present
select is(
    prepare_event_checkout_get_purchase_summary(:'purchaseWithProviderFieldsID'::uuid),
    jsonb_build_object(
        'amount_minor', 2000,
        'charge_model', 'direct-charge',
        'completed_at', 1893579300,
        'currency_code', 'USD',
        'discount_amount_minor', 500,
        'discount_code', 'SAVE20',
        'event_purchase_id', :'purchaseWithProviderFieldsID'::uuid,
        'event_ticket_type_id', :'ticketTypeID'::uuid,
        'hold_expires_at', 1893501000,
        'manual_tax_rate_ids', jsonb_build_array('txr_state'),
        'provisional_platform_fee_amount_minor', 200,
        'provider_checkout_url', 'https://example.com/checkout/cs_get_summary',
        'provider_object_account_id', 'acct_get_summary',
        'provider_payment_reference', 'pi_get_summary',
        'provider_session_id', 'cs_get_summary',
        'provider_total_minor', 2000,
        'refunded_at', 1893660300,
        'seller', '{"connected_account_id":"acct_get_summary","display_name":"Sponsor","provider":"stripe"}'::jsonb,
        'status', 'refunded',
        'tax_behavior', 'inclusive',
        'tax_calculation_mode', 'manual',
        'ticket_title', 'General admission',
        'venue', '{"address":"1 Main St","city":"Portland","country_code":"US","name":"Venue","state_code":"OR","state_name":"Oregon","zip_code":"97201"}'::jsonb
    ),
    'Should return all checkout summary fields when they are present'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
