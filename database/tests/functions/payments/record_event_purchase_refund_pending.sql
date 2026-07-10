-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79510000-0000-0000-0000-000000000001'
\set eventCategoryID '79510000-0000-0000-0000-000000000002'
\set eventID '79510000-0000-0000-0000-000000000003'
\set eventTicketTypeID '79510000-0000-0000-0000-000000000004'
\set groupCategoryID '79510000-0000-0000-0000-000000000005'
\set groupID '79510000-0000-0000-0000-000000000006'
\set missingRefundID '79510000-0000-0000-0000-000000000012'
\set priceWindowID '79510000-0000-0000-0000-000000000007'
\set purchaseID '79510000-0000-0000-0000-000000000008'
\set refundID '79510000-0000-0000-0000-000000000009'
\set refundRequestID '79510000-0000-0000-0000-000000000010'
\set succeededPurchaseID '79510000-0000-0000-0000-000000000013'
\set succeededRefundID '79510000-0000-0000-0000-000000000014'
\set terminalPurchaseID '79510000-0000-0000-0000-000000000015'
\set terminalRefundID '79510000-0000-0000-0000-000000000016'
\set userID '79510000-0000-0000-0000-000000000011'

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
    'record-refund-pending-community',
    'Record Refund Pending Community',
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
values (:'userID', 'hash', 'pending-buyer@example.com', true, 'pending-buyer');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Record Refund Pending Group',
    'record-refund-pending-group'
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
    published,
    published_at
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Record Refund Pending Event',
    'record-refund-pending-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
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

-- Purchases for pending, succeeded, and terminal refund scenarios
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
    :'purchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-requested',
    'General admission',
    :'userID'
), (
    :'succeededPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'userID'
), (
    :'terminalPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'userID'
);

-- Refund request
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'refundRequestID',
    :'purchaseID',
    :'userID',
    'approving'
);

-- Provider refund records for pending, succeeded, and terminal scenarios
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,

    event_refund_request_id,
    failure_message,
    finalized_at,
    provider_refund_id,
    provider_refunded_at
) values (
    :'refundID',
    2500,
    'USD',
    :'purchaseID',
    'event-purchase-refund-' || :'purchaseID',
    'refund-request-approval',
    'stripe',
    'provider-pending',

    :'refundRequestID',
    null,
    null,
    null,
    null
), (
    :'succeededRefundID',
    2500,
    'USD',
    :'succeededPurchaseID',
    'event-purchase-refund-' || :'succeededPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-succeeded',

    null,
    null,
    null,
    're_succeeded_123',
    current_timestamp
), (
    :'terminalRefundID',
    2500,
    'USD',
    :'terminalPurchaseID',
    'event-purchase-refund-' || :'terminalPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',

    null,
    'provider refund failed: re_terminal_123',
    null,
    're_terminal_123',
    null
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject empty expected idempotency keys
select throws_ok(
    format($$select record_event_purchase_refund_pending(
        %L::uuid,
        '   ',
        're_pending_123'
    )$$, :'refundID'),
    'expected idempotency key is required',
    'Should reject empty expected idempotency keys'
);

-- Should reject empty provider refund ids
select throws_ok(
    format($$select record_event_purchase_refund_pending(
        %L::uuid,
        %L,
        '   '
    )$$, :'refundID', 'event-purchase-refund-' || :'purchaseID'),
    'provider refund id is required',
    'Should reject empty provider refund ids'
);

-- Should record provider refund progress on a pending refund row
select is(
    record_event_purchase_refund_pending(
        :'refundID'::uuid,
        'event-purchase-refund-' || :'purchaseID',
        're_pending_123'
    ) - 'event_purchase_refund_id',
    jsonb_build_object(
        'amount_minor', 2500,
        'currency_code', 'USD',
        'event_purchase_id', :'purchaseID'::uuid,
        'idempotency_key', 'event-purchase-refund-' || :'purchaseID',
        'kind', 'refund-request-approval',
        'payment_provider', 'stripe',
        'provider_refund_id', 're_pending_123',
        'started_now', false,
        'status', 'provider-pending'
    ),
    'Should record provider refund progress on a pending refund row'
);

-- Should allow retry with the same provider refund id
select is(
    record_event_purchase_refund_pending(
        :'refundID'::uuid,
        'event-purchase-refund-' || :'purchaseID',
        're_pending_123'
    ) - 'event_purchase_refund_id',
    jsonb_build_object(
        'amount_minor', 2500,
        'currency_code', 'USD',
        'event_purchase_id', :'purchaseID'::uuid,
        'idempotency_key', 'event-purchase-refund-' || :'purchaseID',
        'kind', 'refund-request-approval',
        'payment_provider', 'stripe',
        'provider_refund_id', 're_pending_123',
        'started_now', false,
        'status', 'provider-pending'
    ),
    'Should allow retry with the same provider refund id'
);

-- Should reject conflicting provider refund ids
select throws_ok(
    format($$select record_event_purchase_refund_pending(
        %L::uuid,
        %L,
        're_pending_456'
    )$$, :'refundID', 'event-purchase-refund-' || :'purchaseID'),
    'event purchase refund already has a different provider refund id',
    'Should reject conflicting provider refund ids'
);

-- Should not downgrade provider success to pending
select is(
    record_event_purchase_refund_pending(
        :'succeededRefundID'::uuid,
        'event-purchase-refund-' || :'succeededPurchaseID',
        're_succeeded_123'
    )->>'status',
    'provider-succeeded',
    'Should not downgrade provider success to pending'
);

-- Should not revive terminal provider failure as pending
select is(
    record_event_purchase_refund_pending(
        :'terminalRefundID'::uuid,
        'event-purchase-refund-' || :'terminalPurchaseID',
        're_terminal_123'
    )->>'status',
    'provider-failed',
    'Should not revive terminal provider failure as pending'
);

-- Should reject missing refund rows
select throws_ok(
    format($$select record_event_purchase_refund_pending(
        %L::uuid,
        'event-purchase-refund-missing',
        're_missing_123'
    )$$, :'missingRefundID'),
    'event purchase refund not found',
    'Should reject missing refund rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
