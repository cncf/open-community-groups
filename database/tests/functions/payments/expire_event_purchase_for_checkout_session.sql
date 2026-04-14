-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '71000000-0000-0000-0000-000000000001'
\set discountCodeID '71000000-0000-0000-0000-000000000002'
\set eventCategoryID '71000000-0000-0000-0000-000000000003'
\set eventID '71000000-0000-0000-0000-000000000004'
\set eventTicketTypeID '71000000-0000-0000-0000-000000000005'
\set groupCategoryID '71000000-0000-0000-0000-000000000006'
\set groupID '71000000-0000-0000-0000-000000000007'
\set pendingPurchaseID '71000000-0000-0000-0000-000000000008'
\set completedPurchaseID '71000000-0000-0000-0000-000000000009'
\set completedUserID '71000000-0000-0000-0000-000000000012'
\set priceWindowID '71000000-0000-0000-0000-000000000010'
\set userID '71000000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'expire-community', 'Expire Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

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
    'Expire Group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_test_group'),
    'expire-group'
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
    'Expire Event',
    'expire-event',
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

-- Discount code
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    available,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    500,
    0,
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
    payment_provider_id,
    provider_checkout_session_id,
    status,
    ticket_title,
    user_id
) values (
    :'pendingPurchaseID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_pending',
    'pending',
    'General admission',
    :'userID'
), (
    :'completedPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'eventID',
    :'eventTicketTypeID',
    null,
    'stripe',
    'cs_completed',
    'completed',
    'General admission',
    :'completedUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should expire the matching pending purchase
select lives_ok(
    $$select expire_event_purchase_for_checkout_session('stripe', 'cs_pending')$$,
    'Should expire the matching pending purchase'
);

-- Should mark the pending purchase as expired
select is(
    (
        select status
        from event_purchase
        where event_purchase_id = :'pendingPurchaseID'::uuid
    ),
    'expired',
    'Should mark the pending purchase as expired'
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
    $$select expire_event_purchase_for_checkout_session('stripe', 'cs_missing')$$,
    'Should ignore missing checkout sessions'
);

-- Should leave completed purchases unchanged
select is(
    (
        select status
        from event_purchase
        where event_purchase_id = :'completedPurchaseID'::uuid
    ),
    'completed',
    'Should leave completed purchases unchanged'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
