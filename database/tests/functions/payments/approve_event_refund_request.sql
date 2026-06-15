-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '79400000-0000-0000-0000-000000000001'
\set communityID '79400000-0000-0000-0000-000000000002'
\set discountCodeID '79400000-0000-0000-0000-000000000003'
\set eventCategoryID '79400000-0000-0000-0000-000000000004'
\set eventID '79400000-0000-0000-0000-000000000005'
\set eventTicketTypeID '79400000-0000-0000-0000-000000000006'
\set groupCategoryID '79400000-0000-0000-0000-000000000007'
\set groupID '79400000-0000-0000-0000-000000000008'
\set missingUserID '79400000-0000-0000-0000-000000000009'
\set noDiscountPurchaseID '79400000-0000-0000-0000-000000000010'
\set noDiscountRefundRequestID '79400000-0000-0000-0000-000000000011'
\set noDiscountUserID '79400000-0000-0000-0000-000000000012'
\set pendingPurchaseID '79400000-0000-0000-0000-000000000013'
\set pendingRefundRequestID '79400000-0000-0000-0000-000000000014'
\set pendingUserID '79400000-0000-0000-0000-000000000015'
\set priceWindowID '79400000-0000-0000-0000-000000000016'
\set purchaseID '79400000-0000-0000-0000-000000000017'
\set refundRequestID '79400000-0000-0000-0000-000000000018'
\set userID '79400000-0000-0000-0000-000000000019'

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
    'approve-community',
    'Approve Community',
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
        :'actorUserID',
        'hash-1',
        'actor@example.com',
        true,
        'reviewer'
    ),
    (
        :'noDiscountUserID',
        'hash-3',
        'no-discount-buyer@example.com',
        true,
        'no-discount-buyer'
    ),
    (
        :'pendingUserID',
        'hash-4',
        'pending-buyer@example.com',
        true,
        'pending-buyer'
    ),
    (
        :'userID',
        'hash-2',
        'buyer@example.com',
        true,
        'buyer'
    );

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Approve Group', 'approve-group');

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
    published,
    published_at
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Approve Event',
    'approve-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    true,
    now()
);

-- Ticket type and price window
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
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    500,
    0,
    true,
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
);

-- Purchase
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'noDiscountPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'eventID',
    :'eventTicketTypeID',
    'refund-requested',
    'General admission',
    :'noDiscountUserID'
), (
    :'pendingPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'eventID',
    :'eventTicketTypeID',
    'refund-requested',
    'General admission',
    :'pendingUserID'
), (
    :'purchaseID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'eventTicketTypeID',
    'refund-requested',
    'General admission',
    :'userID'
);

-- Attendee
insert into event_attendee (event_id, user_id)
values
    (:'eventID', :'noDiscountUserID'),
    (:'eventID', :'userID');

-- Refund request
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'noDiscountRefundRequestID',
    :'noDiscountPurchaseID',
    :'noDiscountUserID',
    'approving'
), (
    :'pendingRefundRequestID',
    :'pendingPurchaseID',
    :'pendingUserID',
    'pending'
), (
    :'refundRequestID',
    :'purchaseID',
    :'userID',
    'approving'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should approve an approving refund request
select is(
    approve_event_refund_request(
        :'actorUserID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'userID'::uuid,
        're_test_123',
        'Looks good'
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'user_id', :'userID'::uuid
    ),
    'Should approve an approving refund request'
);

-- Should persist the updated purchase and refund request fields
select results_eq(
    format($$
        select
            (select refunded_at is not null from event_purchase where event_purchase_id = %L::uuid),
            (select status from event_purchase where event_purchase_id = %L::uuid),
            (select review_note from event_refund_request where event_refund_request_id = %L::uuid),
            (select reviewed_at is not null from event_refund_request where event_refund_request_id = %L::uuid),
            (select reviewed_by_user_id from event_refund_request where event_refund_request_id = %L::uuid),
            (select status from event_refund_request where event_refund_request_id = %L::uuid)
    $$, :'purchaseID', :'purchaseID', :'refundRequestID', :'refundRequestID', :'refundRequestID', :'refundRequestID'),
    format(
        $$ values (true, 'refunded'::text, 'Looks good'::text, true, %L::uuid, 'approved'::text) $$,
        :'actorUserID'
    ),
    'Should persist the updated purchase and refund request fields'
);

-- Should restore discount availability and remove the attendee
select results_eq(
    format($$
        select
            (select available from event_discount_code where event_discount_code_id = %L::uuid),
            (select count(*)::int from event_attendee where event_id = %L::uuid and user_id = %L::uuid)
    $$, :'discountCodeID', :'eventID', :'userID'),
    $$ values (1::int, 0::int) $$,
    'Should restore discount availability and remove the attendee'
);

-- Should create the expected refund audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            community_id,
            event_id,
            group_id,
            details->>'event_purchase_id',
            details->>'provider_refund_id',
            details->>'user_id'
        from audit_log
    $$,
    format($$ values (
        'event_refunded'::text,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L,
        're_test_123',
        %L
    ) $$, :'actorUserID', :'communityID', :'eventID', :'groupID', :'purchaseID', :'userID'),
    'Should create the expected refund audit row'
);

-- Should reject refund requests that are not approving
select throws_ok(
    format($$select approve_event_refund_request(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        're_pending',
        null
    )$$, :'actorUserID', :'groupID', :'eventID', :'pendingUserID'),
    'refund request not found',
    'Should reject refund requests that are not approving'
);

-- Should approve a refund request without a discount code
select is(
    approve_event_refund_request(
        :'actorUserID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'noDiscountUserID'::uuid,
        're_no_discount',
        null
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'user_id', :'noDiscountUserID'::uuid
    ),
    'Should approve a refund request without a discount code'
);

-- Should leave discount availability unchanged for purchases without a discount code
select results_eq(
    format($$
        select
            (select status from event_purchase where event_purchase_id = %L::uuid),
            (select status from event_refund_request where event_refund_request_id = %L::uuid),
            (select event_discount_code_id is null from event_purchase where event_purchase_id = %L::uuid),
            (select available from event_discount_code where event_discount_code_id = %L::uuid),
            (select count(*)::int from event_attendee where event_id = %L::uuid and user_id = %L::uuid)
    $$, :'noDiscountPurchaseID', :'noDiscountRefundRequestID', :'noDiscountPurchaseID', :'discountCodeID', :'eventID', :'noDiscountUserID'),
    $$ values ('refunded'::text, 'approved'::text, true, 1::int, 0::int) $$,
    'Should leave discount availability unchanged for purchases without a discount code'
);

-- Should reject missing approving refund requests
select throws_ok(
    format($$select approve_event_refund_request(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        're_missing',
        null
    )$$, :'actorUserID', :'groupID', :'eventID', :'missingUserID'),
    'refund request not found',
    'Should reject missing approving refund requests'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
