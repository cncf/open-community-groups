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
\set ticketTypeID '79240000-0000-0000-0000-000000000004'
\set groupCategoryID '79240000-0000-0000-0000-000000000005'
\set groupID '79240000-0000-0000-0000-000000000006'
\set priceWindowID '79240000-0000-0000-0000-000000000007'
\set purchaseID '79240000-0000-0000-0000-000000000008'
\set userID '79240000-0000-0000-0000-000000000009'
\set purchaseWithProviderFieldsID '79240000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'get-summary-community', 'Get Summary Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

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
insert into "group" (group_id, community_id, group_category_id, name, payment_recipient, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Get Summary Group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_get_summary'),
    'get-summary-group'
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
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'ticketTypeID', :'eventID', 1, 10, 'General admission');

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
    completed_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    refunded_at,
    status,
    ticket_title,
    user_id
) values (
    :'purchaseID',
    2500,
    null,
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeID',
    '2030-01-01 10:00:00+00'::timestamptz,
    null,
    null,
    null,
    null,
    null,
    'pending',
    'General admission',
    :'userID'
), (
    :'purchaseWithProviderFieldsID',
    2000,
    '2030-01-02 10:15:00+00'::timestamptz,
    'USD',
    500,
    'SAVE20',
    :'eventID',
    :'ticketTypeID',
    '2030-01-01 12:30:00+00'::timestamptz,
    'stripe',
    'cs_get_summary',
    'https://example.com/checkout/cs_get_summary',
    'pi_get_summary',
    '2030-01-03 08:45:00+00'::timestamptz,
    'refunded',
    'General admission',
    :'userID'
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
        'status', 'pending',
        'ticket_title', 'General admission'
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
        'provider_checkout_url', 'https://example.com/checkout/cs_get_summary',
        'provider_payment_reference', 'pi_get_summary',
        'provider_session_id', 'cs_get_summary',
        'refunded_at', 1893660300,
        'status', 'refunded',
        'ticket_title', 'General admission'
    ),
    'Should return all checkout summary fields when they are present'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
