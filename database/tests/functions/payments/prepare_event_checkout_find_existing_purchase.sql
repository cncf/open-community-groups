-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79230000-0000-0000-0000-000000000001'
\set eventCategoryID '79230000-0000-0000-0000-000000000002'
\set eventID '79230000-0000-0000-0000-000000000003'
\set ticketTypeAID '79230000-0000-0000-0000-000000000004'
\set ticketTypeBID '79230000-0000-0000-0000-000000000005'
\set groupCategoryID '79230000-0000-0000-0000-000000000006'
\set groupID '79230000-0000-0000-0000-000000000007'
\set priceWindowAID '79230000-0000-0000-0000-000000000008'
\set priceWindowBID '79230000-0000-0000-0000-000000000009'
\set pendingPurchaseID '79230000-0000-0000-0000-000000000010'
\set refundPurchaseID '79230000-0000-0000-0000-000000000011'
\set primaryUserID '79230000-0000-0000-0000-000000000012'
\set secondaryUserID '79230000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'find-reusable-community', 'Find Reusable Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'primaryUserID', 'hash-1', 'primary@example.com', true, 'primary-user'),
    (:'secondaryUserID', 'hash-2', 'secondary@example.com', true, 'secondary-user');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, payment_recipient, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Find Reusable Group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_find_reusable'),
    'find-reusable-group'
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
    'Find Reusable Event',
    'find-reusable-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
);

-- Ticket types
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title) values
    (:'ticketTypeAID', :'eventID', 1, 10, 'General admission'),
    (:'ticketTypeBID', :'eventID', 2, 10, 'VIP');

-- Price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'priceWindowAID', 2500, :'ticketTypeAID'),
    (:'priceWindowBID', 4000, :'ticketTypeBID');

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'pendingPurchaseID',
    2000,
    now() - interval '1 hour',
    'USD',
    500,
    ' save5 ',
    :'eventID',
    :'ticketTypeAID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'primaryUserID'
), (
    :'refundPurchaseID',
    4000,
    now() - interval '30 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'refund-requested',
    'VIP',
    :'secondaryUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the active pending purchase for the requested user and event
select results_eq(
    $$
        select event_purchase_id::text, status
        from prepare_event_checkout_find_existing_purchase(
            '79230000-0000-0000-0000-000000000003'::uuid,
            '79230000-0000-0000-0000-000000000004'::uuid,
            '79230000-0000-0000-0000-000000000012'::uuid,
            'SAVE5'
        )
    $$,
    $$ values ('79230000-0000-0000-0000-000000000010'::text, 'pending'::text) $$,
    'Should return the active pending purchase for the requested user and event'
);

-- Should mark the pending purchase as matching when ticket and discount align
select results_eq(
    $$
        select matches_selection::text
        from prepare_event_checkout_find_existing_purchase(
            '79230000-0000-0000-0000-000000000003'::uuid,
            '79230000-0000-0000-0000-000000000004'::uuid,
            '79230000-0000-0000-0000-000000000012'::uuid,
            'SAVE5'
        )
    $$,
    $$ values ('true'::text) $$,
    'Should mark the pending purchase as matching when ticket and discount align'
);

-- Should mark the pending purchase as mismatched when the requested discount changes
select results_eq(
    $$
        select matches_selection::text
        from prepare_event_checkout_find_existing_purchase(
            '79230000-0000-0000-0000-000000000003'::uuid,
            '79230000-0000-0000-0000-000000000004'::uuid,
            '79230000-0000-0000-0000-000000000012'::uuid,
            'SAVE10'
        )
    $$,
    $$ values ('false'::text) $$,
    'Should mark the pending purchase as mismatched when the requested discount changes'
);

-- Should return refund-requested purchases when no active pending purchase exists
select results_eq(
    $$
        select event_purchase_id::text, matches_selection::text, status
        from prepare_event_checkout_find_existing_purchase(
            '79230000-0000-0000-0000-000000000003'::uuid,
            '79230000-0000-0000-0000-000000000005'::uuid,
            '79230000-0000-0000-0000-000000000013'::uuid,
            null
        )
    $$,
    $$ values ('79230000-0000-0000-0000-000000000011'::text, 'true'::text, 'refund-requested'::text) $$,
    'Should return refund-requested purchases when no active pending purchase exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
