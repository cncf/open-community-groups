-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79300000-0000-0000-0000-000000000001'
\set eventCategoryID '79300000-0000-0000-0000-000000000002'
\set eventDiscountCodeID '79300000-0000-0000-0000-000000000003'
\set eventID '79300000-0000-0000-0000-000000000004'
\set eventPaidTicketTypeID '79300000-0000-0000-0000-000000000010'
\set eventTicketTypeID '79300000-0000-0000-0000-000000000011'
\set freePurchaseID '79300000-0000-0000-0000-000000000005'
\set groupCategoryID '79300000-0000-0000-0000-000000000006'
\set groupID '79300000-0000-0000-0000-000000000007'
\set paidPurchaseID '79300000-0000-0000-0000-000000000008'
\set paidUserID '79300000-0000-0000-0000-000000000012'
\set userID '79300000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'refund-free-community', 'Refund Free Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Refund Free Group', 'refund-free-group');

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'paidUserID', 'hash-2', 'refund-free-paid@example.com', true, 'refund-free-paid-user'),
    (:'userID', 'hash-1', 'refund-free@example.com', true, 'refund-free-user');

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
    'Refund Free Event',
    'refund-free-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
);

-- Discount code
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    code,
    event_id,
    kind,
    title
) values (
    :'eventDiscountCodeID',
    true,
    2500,
    0,
    'FREEPASS',
    :'eventID',
    'fixed_amount',
    'Free pass'
);

-- Event ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values
    (
        :'eventPaidTicketTypeID',
        :'eventID',
        2,
        1,
        'Paid admission'
    ),
    (
        :'eventTicketTypeID',
        :'eventID',
        1,
        1,
        'General admission'
    );

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'freePurchaseID',
    0,
    'USD',
    'FREEPASS',
    :'eventDiscountCodeID',
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'userID'
), (
    :'paidPurchaseID',
    2500,
    'USD',
    null,
    null,
    :'eventID',
    :'eventPaidTicketTypeID',
    'completed',
    'Paid admission',
    :'paidUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should refund the free purchase successfully
select lives_ok(
    $$select refund_free_event_purchase('79300000-0000-0000-0000-000000000005'::uuid)$$,
    'Should refund the free purchase successfully'
);

-- Should mark the purchase as refunded and restore one discount redemption
select results_eq(
    $$
        select
            (
                select status::text
                from event_purchase
                where event_purchase_id = '79300000-0000-0000-0000-000000000005'::uuid
            ),
            (select available from event_discount_code where event_discount_code_id = '79300000-0000-0000-0000-000000000003'::uuid)
    $$,
    $$ values ('refunded'::text, 1::int) $$,
    'Should mark the purchase as refunded and restore one discount redemption'
);

-- Should reject non-free purchases
select throws_ok(
    $$select refund_free_event_purchase('79300000-0000-0000-0000-000000000008'::uuid)$$,
    'free purchase not found',
    'Should reject non-free purchases'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
