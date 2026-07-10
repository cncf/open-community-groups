-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79520000-0000-0000-0000-000000000001'
\set eventCategoryID '79520000-0000-0000-0000-000000000002'
\set eventID '79520000-0000-0000-0000-000000000003'
\set eventTicketTypeID '79520000-0000-0000-0000-000000000004'
\set failedPurchaseID '79520000-0000-0000-0000-000000000005'
\set failedRefundID '79520000-0000-0000-0000-000000000006'
\set failedUserID '79520000-0000-0000-0000-000000000007'
\set groupCategoryID '79520000-0000-0000-0000-000000000008'
\set groupID '79520000-0000-0000-0000-000000000009'
\set missingRefundID '79520000-0000-0000-0000-000000000014'
\set priceWindowID '79520000-0000-0000-0000-000000000010'
\set succeededPurchaseID '79520000-0000-0000-0000-000000000011'
\set succeededRefundID '79520000-0000-0000-0000-000000000012'
\set succeededUserID '79520000-0000-0000-0000-000000000013'

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
    'record-terminal-refund-failure-community',
    'Record Terminal Refund Failure Community',
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
        :'failedUserID',
        'hash-1',
        'terminal-failed-buyer@example.com',
        true,
        'terminal-failed-buyer'
    ),
    (
        :'succeededUserID',
        'hash-2',
        'terminal-succeeded-buyer@example.com',
        true,
        'terminal-succeeded-buyer'
    );

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Record Terminal Refund Failure Group',
    'record-terminal-refund-failure-group'
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
    'Record Terminal Refund Failure Event',
    'record-terminal-refund-failure-event',
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
    :'failedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'failedUserID'
), (
    :'succeededPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'succeededUserID'
);

-- Provider refund records
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,

    provider_refund_id,
    provider_refunded_at
) values (
    :'failedRefundID',
    2500,
    'USD',
    :'failedPurchaseID',
    'event-purchase-refund-' || :'failedPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-pending',

    're_failed_123',
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

    're_success_123',
    current_timestamp
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject empty expected idempotency keys
select throws_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        '   ',
        're_failed_123',
        'provider refund failed'
    )$$, :'failedRefundID'),
    'expected idempotency key is required',
    'Should reject empty expected idempotency keys'
);

-- Should reject empty provider refund ids
select throws_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        '   ',
        'provider refund failed'
    )$$, :'failedRefundID', 'event-purchase-refund-' || :'failedPurchaseID'),
    'provider refund id is required',
    'Should reject empty provider refund ids'
);

-- Should reject a provider refund id that conflicts with the pinned attempt
select throws_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        're_conflict_123',
        'provider refund failed'
    )$$, :'failedRefundID', 'event-purchase-refund-' || :'failedPurchaseID'),
    'event purchase refund already has a different provider refund id',
    'Should reject a provider refund id that conflicts with the pinned attempt'
);

-- Should record terminal provider refund failure
select lives_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        're_failed_123',
        'provider refund failed'
    )$$, :'failedRefundID', 'event-purchase-refund-' || :'failedPurchaseID'),
    'Should record terminal provider refund failure'
);

-- Should unpin the dead provider refund and rotate the idempotency key
select results_eq(
    format($$
        select
            status,
            failure_message,
            provider_refund_id,
            idempotency_key <> 'event-purchase-refund-' || %L,
            idempotency_key like 'event-purchase-refund-' || %L || '-%%'
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'failedPurchaseID', :'failedPurchaseID', :'failedRefundID'),
    $$ values (
        'provider-failed'::text,
        'provider refund failed: re_failed_123'::text,
        null::text,
        true,
        true
    ) $$,
    'Should unpin the dead provider refund and rotate the idempotency key'
);

-- Should ignore a delayed failure from the superseded attempt
select lives_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        're_failed_456',
        'stale provider refund failed'
    )$$, :'failedRefundID', 'event-purchase-refund-' || :'failedPurchaseID'),
    'Should ignore a delayed failure from the superseded attempt'
);

-- Should keep the current attempt state after a delayed failure
select results_eq(
    format($$
        select status, failure_message, provider_refund_id
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'failedRefundID'),
    $$ values ('provider-failed'::text, 'provider refund failed: re_failed_123'::text, null::text) $$,
    'Should keep the current attempt state after a delayed failure'
);

-- Should not downgrade a refund row after provider success is recorded
select lives_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        're_success_123',
        'provider refund failed'
    )$$, :'succeededRefundID', 'event-purchase-refund-' || :'succeededPurchaseID'),
    'Should not downgrade a refund row after provider success is recorded'
);

-- Should keep the successful provider refund state
select results_eq(
    format($$
        select status, provider_refund_id, failure_message
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'succeededRefundID'),
    $$ values ('provider-succeeded'::text, 're_success_123'::text, null::text) $$,
    'Should keep the successful provider refund state'
);

-- Should reject missing refund rows
select throws_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        'event-purchase-refund-missing',
        're_missing_123',
        'provider refund failed'
    )$$, :'missingRefundID'),
    'event purchase refund not found',
    'Should reject missing refund rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
