-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79490000-0000-0000-0000-000000000001'
\set eventCategoryID '79490000-0000-0000-0000-000000000002'
\set eventID '79490000-0000-0000-0000-000000000003'
\set eventTicketTypeID '79490000-0000-0000-0000-000000000004'
\set finalizedPurchaseID '79490000-0000-0000-0000-000000000013'
\set finalizedRefundID '79490000-0000-0000-0000-000000000014'
\set finalizedUserID '79490000-0000-0000-0000-000000000015'
\set groupCategoryID '79490000-0000-0000-0000-000000000005'
\set groupID '79490000-0000-0000-0000-000000000006'
\set missingRefundID '79490000-0000-0000-0000-000000000012'
\set priceWindowID '79490000-0000-0000-0000-000000000007'
\set purchaseID '79490000-0000-0000-0000-000000000008'
\set refundID '79490000-0000-0000-0000-000000000009'
\set refundRequestID '79490000-0000-0000-0000-000000000010'
\set userID '79490000-0000-0000-0000-000000000011'

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
    'record-refund-success-community',
    'Record Refund Success Community',
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

-- Buyers for the pending and finalized refund scenarios
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'finalizedUserID',
        'hash-finalized',
        'finalized-buyer@example.com',
        true,
        'finalized-buyer'
    ),
    (:'userID', 'hash', 'success-buyer@example.com', true, 'success-buyer');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Record Refund Success Group',
    'record-refund-success-group'
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
    'Record Refund Success Event',
    'record-refund-success-event',
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

-- Purchases for the pending and finalized refund scenarios
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
    :'finalizedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refunded',
    'General admission',
    :'finalizedUserID'
), (
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

-- Provider records for the pending and finalized refund scenarios
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
    finalized_at,
    provider_refund_id,
    provider_refunded_at
) values (
    :'finalizedRefundID',
    2500,
    'USD',
    :'finalizedPurchaseID',
    'event-purchase-refund-' || :'finalizedPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'finalized',

    null,
    current_timestamp,
    're_finalized_123',
    current_timestamp
), (
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
    null
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject empty provider refund ids
select throws_ok(
    format($$select record_event_purchase_refund_succeeded(
        %L::uuid,
        '   '
    )$$, :'refundID'),
    'provider refund id is required',
    'Should reject empty provider refund ids'
);

-- Should record provider refund success on a pending refund row
select is(
    record_event_purchase_refund_succeeded(
        :'refundID'::uuid,
        're_success_123'
    ) - 'event_purchase_refund_id' - 'provider_refunded_at',
    jsonb_build_object(
        'amount_minor', 2500,
        'currency_code', 'USD',
        'event_purchase_id', :'purchaseID'::uuid,
        'idempotency_key', 'event-purchase-refund-' || :'purchaseID',
        'kind', 'refund-request-approval',
        'payment_provider', 'stripe',
        'provider_refund_id', 're_success_123',
        'started_now', false,
        'status', 'provider-succeeded'
    ),
    'Should record provider refund success on a pending refund row'
);

-- Should allow retry with the same provider refund id
select is(
    record_event_purchase_refund_succeeded(
        :'refundID'::uuid,
        're_success_123'
    ) - 'event_purchase_refund_id' - 'provider_refunded_at',
    jsonb_build_object(
        'amount_minor', 2500,
        'currency_code', 'USD',
        'event_purchase_id', :'purchaseID'::uuid,
        'idempotency_key', 'event-purchase-refund-' || :'purchaseID',
        'kind', 'refund-request-approval',
        'payment_provider', 'stripe',
        'provider_refund_id', 're_success_123',
        'started_now', false,
        'status', 'provider-succeeded'
    ),
    'Should allow retry with the same provider refund id'
);

-- Should reject conflicting provider refund ids
select throws_ok(
    format($$select record_event_purchase_refund_succeeded(
        %L::uuid,
        're_success_456'
    )$$, :'refundID'),
    'event purchase refund already has a different provider refund id',
    'Should reject conflicting provider refund ids'
);

-- Should not downgrade a locally finalized refund
select is(
    record_event_purchase_refund_succeeded(
        :'finalizedRefundID'::uuid,
        're_finalized_123'
    )->>'status',
    'finalized',
    'Should not downgrade a locally finalized refund'
);

-- Should reject missing refund rows
select throws_ok(
    format($$select record_event_purchase_refund_succeeded(
        %L::uuid,
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
