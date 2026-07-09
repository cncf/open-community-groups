-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set automaticPurchaseID '79460000-0000-0000-0000-000000000001'
\set automaticUserID '79460000-0000-0000-0000-000000000013'
\set completedPurchaseID '79460000-0000-0000-0000-000000000002'
\set completedUserID '79460000-0000-0000-0000-000000000014'
\set communityID '79460000-0000-0000-0000-000000000003'
\set eventCategoryID '79460000-0000-0000-0000-000000000004'
\set eventID '79460000-0000-0000-0000-000000000005'
\set eventTicketTypeID '79460000-0000-0000-0000-000000000006'
\set groupCategoryID '79460000-0000-0000-0000-000000000007'
\set groupID '79460000-0000-0000-0000-000000000008'
\set manualPurchaseID '79460000-0000-0000-0000-000000000009'
\set manualRefundRequestID '79460000-0000-0000-0000-000000000010'
\set manualUserID '79460000-0000-0000-0000-000000000015'
\set missingPurchaseID '79460000-0000-0000-0000-000000000016'
\set priceWindowID '79460000-0000-0000-0000-000000000011'

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
    'ensure-refund-community',
    'Ensure Refund Community',
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
    (:'automaticUserID', 'hash-1', 'automatic@example.com', true, 'automatic-buyer'),
    (:'completedUserID', 'hash-2', 'completed@example.com', true, 'completed-buyer'),
    (:'manualUserID', 'hash-3', 'manual@example.com', true, 'manual-buyer');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Ensure Group', 'ensure-group');

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
    'Ensure Event',
    'ensure-event',
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
    :'automaticPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'automaticUserID'
), (
    :'completedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'completedUserID'
), (
    :'manualPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-requested',
    'General admission',
    :'manualUserID'
);

-- Refund request
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'manualRefundRequestID',
    :'manualPurchaseID',
    :'manualUserID',
    'approving'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject empty payment provider ids
select throws_ok(
    format($$select ensure_event_purchase_refund_started(
        %L::uuid,
        '   ',
        'refund-request-approval'
    )$$, :'manualPurchaseID'),
    'payment provider id is required',
    'Should reject empty payment provider ids'
);

-- Should create a manual refund record before the provider call
select is(
    ensure_event_purchase_refund_started(
        :'manualPurchaseID'::uuid,
        'stripe',
        'refund-request-approval'
    ) - 'event_purchase_refund_id',
    jsonb_build_object(
        'amount_minor', 2500,
        'currency_code', 'USD',
        'event_purchase_id', :'manualPurchaseID'::uuid,
        'idempotency_key', 'event-purchase-refund-' || :'manualPurchaseID',
        'kind', 'refund-request-approval',
        'payment_provider', 'stripe',
        'started_now', true,
        'status', 'provider-pending'
    ),
    'Should create a manual refund record before the provider call'
);

-- Should return the existing manual refund record on retry
select is(
    ensure_event_purchase_refund_started(
        :'manualPurchaseID'::uuid,
        'stripe',
        'refund-request-approval'
    ) - 'event_purchase_refund_id',
    jsonb_build_object(
        'amount_minor', 2500,
        'currency_code', 'USD',
        'event_purchase_id', :'manualPurchaseID'::uuid,
        'idempotency_key', 'event-purchase-refund-' || :'manualPurchaseID',
        'kind', 'refund-request-approval',
        'payment_provider', 'stripe',
        'started_now', false,
        'status', 'provider-pending'
    ),
    'Should return the existing manual refund record on retry'
);

-- Should reject retries with a different payments provider
select throws_ok(
    format($$select ensure_event_purchase_refund_started(
        %L::uuid,
        'other-provider',
        'refund-request-approval'
    )$$, :'manualPurchaseID'),
    'event purchase refund already started with different provider or kind',
    'Should reject retries with a different payments provider'
);

-- Rotate the provider attempt to verify ensure returns the current durable state
select record_event_purchase_refund_terminal_failed(
    (
        select event_purchase_refund_id
        from event_purchase_refund
        where event_purchase_id = :'manualPurchaseID'::uuid
    ),
    'event-purchase-refund-' || :'manualPurchaseID',
    're_failed_manual_123',
    'provider refund failed'
);

-- Should return a rotated idempotency key after terminal provider failure
select ok(
    (
        with refund as (
            select ensure_event_purchase_refund_started(
                :'manualPurchaseID'::uuid,
                'stripe',
                'refund-request-approval'
            ) as data
        )
        select data @> jsonb_build_object(
            'amount_minor', 2500,
            'currency_code', 'USD',
            'event_purchase_id', :'manualPurchaseID'::uuid,
            'kind', 'refund-request-approval',
            'payment_provider', 'stripe',
            'started_now', false,
            'status', 'provider-failed'
        )
        and data->>'idempotency_key' <> 'event-purchase-refund-' || :'manualPurchaseID'
        and data->>'idempotency_key' like 'event-purchase-refund-' || :'manualPurchaseID' || '-%'
        and data ? 'failure_message'
        and not data ? 'provider_refund_id'
        from refund
    ),
    'Should return a rotated idempotency key after terminal provider failure'
);

-- Should create an automatic refund record before the provider call
select is(
    ensure_event_purchase_refund_started(
        :'automaticPurchaseID'::uuid,
        'stripe',
        'automatic-unfulfillable-checkout'
    ) - 'event_purchase_refund_id',
    jsonb_build_object(
        'amount_minor', 2500,
        'currency_code', 'USD',
        'event_purchase_id', :'automaticPurchaseID'::uuid,
        'idempotency_key', 'event-purchase-refund-' || :'automaticPurchaseID',
        'kind', 'automatic-unfulfillable-checkout',
        'payment_provider', 'stripe',
        'started_now', true,
        'status', 'provider-pending'
    ),
    'Should create an automatic refund record before the provider call'
);

-- Should reject unsupported refund kinds
select throws_ok(
    format($$select ensure_event_purchase_refund_started(
        %L::uuid,
        'stripe',
        'unsupported'
    )$$, :'manualPurchaseID'),
    'unsupported refund kind: unsupported',
    'Should reject unsupported refund kinds'
);

-- Should reject automatic refunds for non-refund-pending purchases
select throws_ok(
    format($$select ensure_event_purchase_refund_started(
        %L::uuid,
        'stripe',
        'automatic-unfulfillable-checkout'
    )$$, :'completedPurchaseID'),
    'refund-pending purchase not found',
    'Should reject automatic refunds for non-refund-pending purchases'
);

-- Should reject manual refunds without an approving request
select throws_ok(
    format($$select ensure_event_purchase_refund_started(
        %L::uuid,
        'stripe',
        'refund-request-approval'
    )$$, :'completedPurchaseID'),
    'refund request not found',
    'Should reject manual refunds without an approving request'
);

-- Should reject missing purchases
select throws_ok(
    format($$select ensure_event_purchase_refund_started(
        %L::uuid,
        'stripe',
        'automatic-unfulfillable-checkout'
    )$$, :'missingPurchaseID'),
    'event purchase not found',
    'Should reject missing purchases'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
