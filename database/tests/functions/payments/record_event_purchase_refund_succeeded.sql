-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

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
\set invalidPurchaseID '79490000-0000-0000-0000-000000000016'
\set invalidRefundID '79490000-0000-0000-0000-000000000017'
\set invalidUserID '79490000-0000-0000-0000-000000000018'
\set missingRefundID '79490000-0000-0000-0000-000000000012'
\set priceWindowID '79490000-0000-0000-0000-000000000007'
\set purchaseID '79490000-0000-0000-0000-000000000008'
\set refundID '79490000-0000-0000-0000-000000000009'
\set refundRequestID '79490000-0000-0000-0000-000000000010'
\set terminalPurchaseID '79490000-0000-0000-0000-000000000019'
\set terminalRefundID '79490000-0000-0000-0000-000000000020'
\set terminalUserID '79490000-0000-0000-0000-000000000021'
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

-- Buyers for the pending, finalized, and invalid recovery scenarios
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'finalizedUserID',
        'hash-finalized',
        'finalized-buyer@example.com',
        true,
        'finalized-buyer'
    ),
    (
        :'invalidUserID',
        'hash-invalid',
        'invalid-buyer@example.com',
        true,
        'invalid-buyer'
    ),
    (
        :'terminalUserID',
        'hash-terminal',
        'terminal-buyer@example.com',
        true,
        'terminal-buyer'
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

-- Purchases for the pending, finalized, and invalid recovery scenarios
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
    'refund-recovery-pending',
    'General admission',
    :'finalizedUserID'
), (
    :'invalidPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'invalidUserID'
), (
    :'terminalPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'terminalUserID'
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

-- Provider records for the pending, finalized, and invalid recovery scenarios
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
    :'finalizedRefundID',
    2500,
    'USD',
    :'finalizedPurchaseID',
    'event-purchase-refund-' || :'finalizedPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',

    null,
    'provider refund failed: re_failed_123',
    current_timestamp,
    null,
    null
), (
    :'invalidRefundID',
    2500,
    'USD',
    :'invalidPurchaseID',
    'event-purchase-refund-' || :'invalidPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',

    null,
    'provider refund failed: re_invalid_123',
    current_timestamp,
    null,
    null
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
    null,
    null
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
    format($$select record_event_purchase_refund_succeeded(
        %L::uuid,
        '   ',
        're_success_123'
    )$$, :'refundID'),
    'expected idempotency key is required',
    'Should reject empty expected idempotency keys'
);

-- Should reject empty provider refund ids
select throws_ok(
    format($$select record_event_purchase_refund_succeeded(
        %L::uuid,
        %L,
        '   '
    )$$, :'refundID', 'event-purchase-refund-' || :'purchaseID'),
    'provider refund id is required',
    'Should reject empty provider refund ids'
);

-- Should record provider refund success on a pending refund row
select is(
    record_event_purchase_refund_succeeded(
        :'refundID'::uuid,
        'event-purchase-refund-' || :'purchaseID',
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
        'event-purchase-refund-' || :'purchaseID',
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
        %L,
        're_success_456'
    )$$, :'refundID', 'event-purchase-refund-' || :'purchaseID'),
    'event purchase refund already has a different provider refund id',
    'Should reject conflicting provider refund ids'
);

-- Should ignore a successful result from a superseded attempt
select results_eq(
    format($$
        with stale_success as materialized (
            select record_event_purchase_refund_succeeded(
                %L::uuid,
                'event-purchase-refund-stale',
                're_stale_123'
            )
        )
        select provider_refund_id, status
        from event_purchase_refund
        cross join stale_success
        where event_purchase_refund_id = %L::uuid
    $$, :'refundID', :'refundID'),
    $$ values ('re_success_123'::text, 'provider-succeeded'::text) $$,
    'Should ignore a successful result from a superseded attempt'
);

-- Should not revive a terminal provider refund with delayed success
select results_eq(
    format($$
        with delayed_success as materialized (
            select record_event_purchase_refund_succeeded(
                %L::uuid,
                %L,
                're_terminal_123'
            )
        )
        select failure_message, provider_refund_id, status
        from event_purchase_refund
        cross join delayed_success
        where event_purchase_refund_id = %L::uuid
    $$,
        :'terminalRefundID',
        'event-purchase-refund-' || :'terminalPurchaseID',
        :'terminalRefundID'
    ),
    $$ values (
        'provider refund failed: re_terminal_123'::text,
        're_terminal_123'::text,
        'provider-failed'::text
    ) $$,
    'Should not revive a terminal provider refund with delayed success'
);

-- Should reject finalized refunds whose purchase is not recoverable
select throws_ok(
    format($$select record_event_purchase_refund_succeeded(
        %L::uuid,
        %L,
        're_invalid_123'
    )$$, :'invalidRefundID', 'event-purchase-refund-' || :'invalidPurchaseID'),
    'finalized event purchase not found',
    'Should reject finalized refunds whose purchase is not recoverable'
);

-- Should preserve invalid refund and purchase state after rejection
select results_eq(
    format($$
        select epr.failure_message, epr.provider_refund_id, epr.status, ep.status
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'invalidRefundID'),
    $$ values (
        'provider refund failed: re_invalid_123'::text,
        null::text,
        'provider-failed'::text,
        'completed'::text
    ) $$,
    'Should preserve invalid refund and purchase state after rejection'
);

-- Should finalize a success after an uncertain provider outcome
select is(
    record_event_purchase_refund_succeeded(
        :'finalizedRefundID'::uuid,
        'event-purchase-refund-' || :'finalizedPurchaseID',
        're_recovery_123'
    )->>'status',
    'finalized',
    'Should finalize a success after an uncertain provider outcome'
);

-- Should restore the refunded purchase after provider recovery
select results_eq(
    format($$
        select
            epr.failure_message,
            epr.provider_refund_id,
            epr.provider_refunded_at is not null,
            ep.status
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'finalizedRefundID'),
    $$ values (null::text, 're_recovery_123'::text, true, 'refunded'::text) $$,
    'Should restore the refunded purchase after provider recovery'
);

-- Should preserve the purchase timestamp on successful replay
select results_eq(
    format($$
        with before_replay as materialized (
            select updated_at
            from event_purchase
            where event_purchase_id = %L::uuid
        ),
        replay as materialized (
            select record_event_purchase_refund_succeeded(
                %L::uuid,
                %L,
                're_recovery_123'
            )
            from before_replay
        )
        select ep.updated_at = br.updated_at
        from event_purchase ep
        cross join before_replay br
        cross join replay
        where ep.event_purchase_id = %L::uuid
    $$,
        :'finalizedPurchaseID',
        :'finalizedRefundID',
        'event-purchase-refund-' || :'finalizedPurchaseID',
        :'finalizedPurchaseID'
    ),
    $$ values (true) $$,
    'Should preserve the purchase timestamp on successful replay'
);

-- Should reject missing refund rows
select throws_ok(
    format($$select record_event_purchase_refund_succeeded(
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
