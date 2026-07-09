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

-- Purchase
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

-- Provider refund record
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,

    event_refund_request_id
) values (
    :'refundID',
    2500,
    'USD',
    :'purchaseID',
    'event-purchase-refund-' || :'purchaseID',
    'refund-request-approval',
    'stripe',
    'provider-pending',

    :'refundRequestID'
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

-- Rotate the provider attempt to verify stale pending results are ignored
select record_event_purchase_refund_terminal_failed(
    :'refundID'::uuid,
    'event-purchase-refund-' || :'purchaseID',
    're_pending_123',
    'provider refund failed'
);

-- Should ignore a delayed pending result from the superseded attempt
select is(
    record_event_purchase_refund_pending(
        :'refundID'::uuid,
        'event-purchase-refund-' || :'purchaseID',
        're_pending_123'
    )->>'status',
    'provider-failed',
    'Should ignore a delayed pending result from the superseded attempt'
);

-- Record provider success to verify pending updates cannot downgrade it
select record_event_purchase_refund_succeeded(
    :'refundID'::uuid,
    're_succeeded_123'
);

-- Should not downgrade provider success to pending
select is(
    record_event_purchase_refund_pending(
        :'refundID'::uuid,
        (
            select idempotency_key
            from event_purchase_refund
            where event_purchase_refund_id = :'refundID'::uuid
        ),
        're_succeeded_123'
    )->>'status',
    'provider-succeeded',
    'Should not downgrade provider success to pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
