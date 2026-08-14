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
    'get-summary-community',
    'Get Summary Community',
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

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash-1', 'buyer@example.com', true, 'buyer');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    payment_recipient
)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Get Summary Group',
    'get-summary-group',
    jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_get_summary',
        'seller_display_name', 'Purchase Summary Fiscal Sponsor'
    )
);

-- Event
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
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Get Summary Event',
    'get-summary-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
);

-- Ticket type
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeID',
    :'eventID',
    1,
    10,
    'General admission'
);

-- Price window
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    2500,
    :'ticketTypeID'
);

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
    manual_tax_snapshot,
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
    '[]'::jsonb,
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
    '[]'::jsonb,
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
        'currency_code', 'USD',
        'discount_amount_minor', 0,
        'event_purchase_id', :'purchaseID'::uuid,
        'event_ticket_type_id', :'ticketTypeID'::uuid,
        'hold_expires_at', 1893492000,
        'manual_tax_components', '[]'::jsonb,
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
        'completed_at', 1893579300,
        'currency_code', 'USD',
        'discount_amount_minor', 500,
        'discount_code', 'SAVE20',
        'event_purchase_id', :'purchaseWithProviderFieldsID'::uuid,
        'event_ticket_type_id', :'ticketTypeID'::uuid,
        'hold_expires_at', 1893501000,
        'manual_tax_components', '[]'::jsonb,
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
