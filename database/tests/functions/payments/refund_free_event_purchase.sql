-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '79320000-0000-0000-0000-000000000001'
\set eventCategoryID '79320000-0000-0000-0000-000000000002'
\set eventDiscountCodeID '79320000-0000-0000-0000-000000000003'
\set eventID '79320000-0000-0000-0000-000000000004'
\set eventPaidTicketTypeID '79320000-0000-0000-0000-000000000010'
\set eventTicketTypeID '79320000-0000-0000-0000-000000000011'
\set freePurchaseID '79320000-0000-0000-0000-000000000005'
\set groupCategoryID '79320000-0000-0000-0000-000000000006'
\set groupID '79320000-0000-0000-0000-000000000007'
\set paidPurchaseID '79320000-0000-0000-0000-000000000008'
\set paidUserID '79320000-0000-0000-0000-000000000012'
\set refundRequestedPurchaseID '79320000-0000-0000-0000-000000000013'
\set refundRequestedRefundRequestID '79320000-0000-0000-0000-000000000014'
\set refundRequestedUserID '79320000-0000-0000-0000-000000000015'
\set userID '79320000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'refund-free-alliance',
    'Refund Free Alliance',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'paidUserID',
        'hash-2',
        'refund-free-paid@example.com',
        true,
        'refund-free-paid-user'
    ),
    (
        :'refundRequestedUserID',
        'hash-3',
        'refund-free-requested@example.com',
        true,
        'refund-free-requested-user'
    ),
    (
        :'userID',
        'hash-1',
        'refund-free@example.com',
        true,
        'refund-free-user'
    );

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Refund Free Group',
    'refund-free-group'
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
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'eventDiscountCodeID',
    true,
    2500,
    0,
    true,
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
    :'refundRequestedPurchaseID',
    0,
    'USD',
    'FREEPASS',
    :'eventDiscountCodeID',
    :'eventID',
    :'eventTicketTypeID',
    'refund-requested',
    'General admission',
    :'refundRequestedUserID'
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

-- Refund request
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'refundRequestedRefundRequestID',
    :'refundRequestedPurchaseID',
    :'refundRequestedUserID',
    'approving'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should refund the free purchase successfully
select lives_ok(
    format($$select refund_free_event_purchase(%L::uuid)$$, :'freePurchaseID'),
    'Should refund the free purchase successfully'
);

-- Should mark the purchase as refunded and restore one discount redemption
select results_eq(
    format($$
        select
            (
                select status::text
                from event_purchase
                where event_purchase_id = %L::uuid
            ),
            (select available from event_discount_code where event_discount_code_id = %L::uuid)
    $$, :'freePurchaseID', :'eventDiscountCodeID'),
    $$ values ('refunded'::text, 1::int) $$,
    'Should mark the purchase as refunded and restore one discount redemption'
);

-- Should refund a refund-requested free purchase successfully
select lives_ok(
    format($$select refund_free_event_purchase(%L::uuid)$$, :'refundRequestedPurchaseID'),
    'Should refund a refund-requested free purchase successfully'
);

-- Should mark the refund-requested purchase as refunded
select results_eq(
    format($$
        select
            (
                select status::text
                from event_purchase
                where event_purchase_id = %L::uuid
            ),
            (
                select status::text
                from event_refund_request
                where event_refund_request_id = %L::uuid
            ),
            (select available from event_discount_code where event_discount_code_id = %L::uuid)
    $$, :'refundRequestedPurchaseID', :'refundRequestedRefundRequestID', :'eventDiscountCodeID'),
    $$ values ('refunded'::text, 'approving'::text, 2::int) $$,
    'Should mark the refund-requested purchase as refunded'
);

-- Should reject non-free purchases
select throws_ok(
    format($$select refund_free_event_purchase(%L::uuid)$$, :'paidPurchaseID'),
    'free purchase not found',
    'Should reject non-free purchases'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
