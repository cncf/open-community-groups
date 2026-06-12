-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attachedPendingPurchaseID '79410000-0000-0000-0000-000000000001'
\set attachedUserID '79410000-0000-0000-0000-000000000002'
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
    'payments-community',
    'Payments Community',
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
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'attachedUserID',
        'hash-3',
        'attached@example.com',
        true,
        'attached-buyer'
    ),
    (
        :'completedUserID',
        'hash-2',
        'completed@example.com',
        true,
        'completed-buyer'
    ),
    (
        :'userID',
        'hash',
        'user@example.com',
        true,
        'buyer'
    );

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
    'Payments Group',
    'payments-group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_test_group')
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
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'eventTicketTypeID',
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

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url
) values (
    :'attachedPendingPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'pending',
    'General admission',
    :'attachedUserID',

    'stripe',
    'cs_existing',
    'https://example.com/existing'
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
