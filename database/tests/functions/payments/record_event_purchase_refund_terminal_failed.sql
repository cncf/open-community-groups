-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

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
\set finalizedPurchaseID '79520000-0000-0000-0000-000000000015'
\set finalizedRefundID '79520000-0000-0000-0000-000000000016'
\set finalizedUserID '79520000-0000-0000-0000-000000000017'
\set groupCategoryID '79520000-0000-0000-0000-000000000008'
\set groupID '79520000-0000-0000-0000-000000000009'
\set invalidPurchaseID '79520000-0000-0000-0000-000000000019'
\set invalidRefundID '79520000-0000-0000-0000-000000000020'
\set invalidUserID '79520000-0000-0000-0000-000000000021'
\set missingRefundID '79520000-0000-0000-0000-000000000014'
\set priceWindowID '79520000-0000-0000-0000-000000000010'
\set recoveryPurchaseID '79520000-0000-0000-0000-000000000022'
\set recoveryRefundID '79520000-0000-0000-0000-000000000023'
\set recoveryUserID '79520000-0000-0000-0000-000000000024'
\set replacementPurchaseID '79520000-0000-0000-0000-000000000018'
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
        :'finalizedUserID',
        'hash-3',
        'terminal-finalized-buyer@example.com',
        true,
        'terminal-finalized-buyer'
    ),
    (
        :'invalidUserID',
        'hash-4',
        'terminal-invalid-buyer@example.com',
        true,
        'terminal-invalid-buyer'
    ),
    (
        :'recoveryUserID',
        'hash-5',
        'terminal-recovery-buyer@example.com',
        true,
        'terminal-recovery-buyer'
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
    user_id,

    refunded_at
) values (
    :'failedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'failedUserID',

    null
), (
    :'finalizedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refunded',
    'General admission',
    :'finalizedUserID',

    current_timestamp
), (
    :'invalidPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'invalidUserID',

    null
), (
    :'recoveryPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-recovery-pending',
    'General admission',
    :'recoveryUserID',

    current_timestamp
), (
    :'replacementPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'finalizedUserID',

    null
), (
    :'succeededPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'succeededUserID',

    null
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

    finalized_at,
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

    null,
    're_failed_123',
    null
), (
    :'finalizedRefundID',
    2500,
    'USD',
    :'finalizedPurchaseID',
    'event-purchase-refund-' || :'finalizedPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'finalized',

    current_timestamp,
    're_finalized_123',
    current_timestamp
), (
    :'invalidRefundID',
    2500,
    'USD',
    :'invalidPurchaseID',
    'event-purchase-refund-' || :'invalidPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'finalized',

    current_timestamp,
    're_invalid_123',
    current_timestamp
), (
    :'recoveryRefundID',
    2500,
    'USD',
    :'recoveryPurchaseID',
    'event-purchase-refund-' || :'recoveryPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',

    current_timestamp,
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

-- Should pin the terminal provider refund without rotating its idempotency key
select results_eq(
    format($$
        select
            status,
            failure_message,
            provider_refund_id,
            idempotency_key = 'event-purchase-refund-' || %L
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'failedPurchaseID', :'failedRefundID'),
    $$ values (
        'provider-failed'::text,
        'provider refund failed: re_failed_123'::text,
        're_failed_123'::text,
        true
    ) $$,
    'Should pin the terminal provider refund without rotating its idempotency key'
);

-- Should accept a duplicate terminal provider failure as an idempotent replay
select lives_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        're_failed_123',
        'duplicate provider refund failed'
    )$$, :'failedRefundID', 'event-purchase-refund-' || :'failedPurchaseID'),
    'Should accept a duplicate terminal provider failure as an idempotent replay'
);

-- Should preserve the first terminal provider failure on replay
select results_eq(
    format($$
        select
            status,

            failure_message,
            provider_refund_id
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'failedRefundID'),
    $$ values (
        'provider-failed'::text,

        'provider refund failed: re_failed_123'::text,
        're_failed_123'::text
    ) $$,
    'Should preserve the first terminal provider failure on replay'
);

-- Should ignore a delayed failure from the superseded attempt
select lives_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        're_failed_456',
        'stale provider refund failed'
    )$$, :'failedRefundID', 'event-purchase-refund-stale'),
    'Should ignore a delayed failure from the superseded attempt'
);

-- Should keep the current attempt state after a delayed failure
select results_eq(
    format($$
        select status, failure_message, provider_refund_id
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'failedRefundID'),
    $$ values (
        'provider-failed'::text,
        'provider refund failed: re_failed_123'::text,
        're_failed_123'::text
    ) $$,
    'Should keep the current attempt state after a delayed failure'
);

-- Should record a delayed failure after provider success
select lives_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        're_success_123',
        'provider refund failed'
    )$$, :'succeededRefundID', 'event-purchase-refund-' || :'succeededPurchaseID'),
    'Should record a delayed failure after provider success'
);

-- Should pin the provider-succeeded attempt after its delayed failure
select results_eq(
    format($$
        select status, failure_message, provider_refund_id, provider_refunded_at
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'succeededRefundID'),
    $$ values (
        'provider-failed'::text,
        'provider refund failed: re_success_123'::text,
        're_success_123'::text,
        null::timestamptz
    ) $$,
    'Should pin the provider-succeeded attempt after its delayed failure'
);

-- Should record a delayed failure after local finalization
select lives_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        're_finalized_123',
        'provider refund failed'
    )$$, :'finalizedRefundID', 'event-purchase-refund-' || :'finalizedPurchaseID'),
    'Should record a delayed failure after local finalization'
);

-- Should preserve local finalization and expose purchase recovery
select results_eq(
    format($$
        select
            epr.status,
            epr.finalized_at is not null,
            epr.provider_refund_id,
            epr.provider_refunded_at,
            ep.status,
            (
                select status
                from event_purchase
                where event_purchase_id = %L::uuid
            )
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'replacementPurchaseID', :'finalizedRefundID'),
    $$ values (
        'provider-failed'::text,
        true,
        're_finalized_123'::text,
        null::timestamptz,
        'refund-recovery-pending'::text,
        'completed'::text
    ) $$,
    'Should preserve local finalization and expose purchase recovery'
);

-- Should preserve recovery state after another terminal failure
select lives_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        're_recovery_again_123',
        'provider refund failed again'
    )$$, :'recoveryRefundID', 'event-purchase-refund-' || :'recoveryPurchaseID'),
    'Should preserve recovery state after another terminal failure'
);

-- Should pin the repeated failed attempt without clearing finalization
select results_eq(
    format($$
        select epr.finalized_at is not null, epr.provider_refund_id, epr.status, ep.status
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'recoveryRefundID'),
    $$ values (
        true,
        're_recovery_again_123'::text,
        'provider-failed'::text,
        'refund-recovery-pending'::text
    ) $$,
    'Should pin the repeated failed attempt without clearing finalization'
);

-- Should reject finalized refunds whose purchase is not recoverable
select throws_ok(
    format($$select record_event_purchase_refund_terminal_failed(
        %L::uuid,
        %L,
        're_invalid_123',
        'provider refund failed'
    )$$, :'invalidRefundID', 'event-purchase-refund-' || :'invalidPurchaseID'),
    'finalized event purchase not found',
    'Should reject finalized refunds whose purchase is not recoverable'
);

-- Should preserve invalid refund and purchase state after rejection
select results_eq(
    format($$
        select epr.provider_refund_id, epr.status, ep.status
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'invalidRefundID'),
    $$ values ('re_invalid_123'::text, 'finalized'::text, 'completed'::text) $$,
    'Should preserve invalid refund and purchase state after rejection'
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
