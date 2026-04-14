-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '70000000-0000-0000-0000-000000000001'
\set eventCategoryID '70000000-0000-0000-0000-000000000002'
\set eventID '70000000-0000-0000-0000-000000000003'
\set eventTicketTypeID '70000000-0000-0000-0000-000000000004'
\set groupCategoryID '70000000-0000-0000-0000-000000000005'
\set groupID '70000000-0000-0000-0000-000000000006'
\set pendingPurchaseID '70000000-0000-0000-0000-000000000007'
\set completedPurchaseID '70000000-0000-0000-0000-000000000008'
\set completedUserID '70000000-0000-0000-0000-000000000011'
\set priceWindowID '70000000-0000-0000-0000-000000000009'
\set userID '70000000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'payments-community', 'Payments Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'userID', 'hash', 'user@example.com', true, 'buyer'),
    (:'completedUserID', 'hash-2', 'completed@example.com', true, 'completed-buyer');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, payment_recipient, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Payments Group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_test_group'),
    'payments-group'
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
    'Checkout Event',
    'checkout-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
);

-- Ticket type
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'eventTicketTypeID', :'eventID', 1, 10, 'General admission');

-- Price window
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    2500,
    :'eventTicketTypeID'
);

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'pendingPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'pending',
    'General admission',
    :'userID'
), (
    :'completedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'completedUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should link checkout session details to a pending purchase
select lives_ok(
    $$
        select attach_checkout_session_to_event_purchase(
            '70000000-0000-0000-0000-000000000007'::uuid,
            'stripe',
            'cs_test_123',
            'https://example.com/checkout'
        )
    $$,
    'Should link checkout session details to a pending purchase'
);

-- Should persist the provider checkout session details
select results_eq(
    $$
        select
            payment_provider_id,
            provider_checkout_session_id,
            provider_checkout_url
        from event_purchase
        where event_purchase_id = '70000000-0000-0000-0000-000000000007'::uuid
    $$,
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
    $$
        select attach_checkout_session_to_event_purchase(
            '70000000-0000-0000-0000-000000000008'::uuid,
            'stripe',
            'cs_completed',
            'https://example.com/completed'
        )
    $$,
    'Should ignore non-pending purchases'
);

-- Should leave completed purchases unchanged
select results_eq(
    $$
        select
            payment_provider_id,
            provider_checkout_session_id,
            provider_checkout_url
        from event_purchase
        where event_purchase_id = '70000000-0000-0000-0000-000000000008'::uuid
    $$,
    $$ values (null::text, null::text, null::text) $$,
    'Should leave completed purchases unchanged'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
