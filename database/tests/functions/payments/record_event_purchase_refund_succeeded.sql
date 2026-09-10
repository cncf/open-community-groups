-- Tests recording successful event purchase refunds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79490000-0000-0000-0000-000000000001'
\set claimedJobID '79490000-0000-0000-0000-000000000027'
\set claimedPurchaseID '79490000-0000-0000-0000-000000000024'
\set claimedRefundID '79490000-0000-0000-0000-000000000025'
\set claimedUserID '79490000-0000-0000-0000-000000000026'
\set eventCategoryID '79490000-0000-0000-0000-000000000002'
\set eventID '79490000-0000-0000-0000-000000000003'
\set eventTicketTypeID '79490000-0000-0000-0000-000000000004'
\set finalizedJobID '79490000-0000-0000-0000-000000000028'
\set finalizedPurchaseID '79490000-0000-0000-0000-000000000013'
\set finalizedRefundID '79490000-0000-0000-0000-000000000014'
\set finalizedUserID '79490000-0000-0000-0000-000000000015'
\set groupCategoryID '79490000-0000-0000-0000-000000000005'
\set groupID '79490000-0000-0000-0000-000000000006'
\set invalidJobID '79490000-0000-0000-0000-000000000029'
\set invalidPurchaseID '79490000-0000-0000-0000-000000000016'
\set invalidRefundID '79490000-0000-0000-0000-000000000017'
\set invalidUserID '79490000-0000-0000-0000-000000000018'
\set missingRefundID '79490000-0000-0000-0000-000000000012'
\set priceWindowID '79490000-0000-0000-0000-000000000007'
\set processingClaimID '79490000-0000-0000-0000-000000000022'
\set purchaseID '79490000-0000-0000-0000-000000000008'
\set refundID '79490000-0000-0000-0000-000000000009'
\set refundJobID '79490000-0000-0000-0000-000000000030'
\set refundRequestID '79490000-0000-0000-0000-000000000010'
\set staleClaimID '79490000-0000-0000-0000-000000000023'
\set terminalJobID '79490000-0000-0000-0000-000000000031'
\set terminalPurchaseID '79490000-0000-0000-0000-000000000019'
\set terminalRefundID '79490000-0000-0000-0000-000000000020'
\set terminalUserID '79490000-0000-0000-0000-000000000021'
\set userID '79490000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'claimedUserID');
select fx_user(:'finalizedUserID');
select fx_user(:'invalidUserID');
select fx_user(:'terminalUserID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- Ticket type
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Price window
select fx_event_ticket_price_window(:'priceWindowID', :'eventTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Purchases for claimed, pending, finalized, and invalid recovery scenarios
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    provisional_platform_fee_amount_minor,
    seller_snapshot,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
) values (
    :'claimedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'claimedUserID',
    'direct-charge', 'acct_refunds', 0, 'stripe', 'ch_succeeded_claimed',
    'cs_succeeded_claimed', 'acct_refunds', 'pi_succeeded_claimed', 2500,
    0,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
), (
    :'finalizedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-recovery-pending',
    'General admission',
    :'finalizedUserID',
    'direct-charge', 'acct_refunds', 0, 'stripe', 'ch_succeeded_finalized',
    'cs_succeeded_finalized', 'acct_refunds', 'pi_succeeded_finalized', 2500,
    0,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
), (
    :'invalidPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'invalidUserID',
    'direct-charge', 'acct_refunds', 0, 'stripe', 'ch_succeeded_invalid',
    'cs_succeeded_invalid', 'acct_refunds', 'pi_succeeded_invalid', 2500,
    0,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
), (
    :'terminalPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'terminalUserID',
    'direct-charge', 'acct_refunds', 0, 'stripe', 'ch_succeeded_terminal',
    'cs_succeeded_terminal', 'acct_refunds', 'pi_succeeded_terminal', 2500,
    0,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
), (
    :'purchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-requested',
    'General admission',
    :'userID',
    'direct-charge', 'acct_refunds', 100, 'stripe', 'ch_succeeded_requested',
    'cs_succeeded_requested', 'acct_refunds', 'pi_succeeded_requested', 2500,
    100,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
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

-- Payment jobs for claimed, pending, finalized, and invalid recovery scenarios
insert into payment_job (
    payment_job_id, attempt_count, event_purchase_id, failure_message,
    idempotency_key, kind, payment_provider_id, status,

    claim_id, claimed_at
) values (
    :'claimedJobID', 1, :'claimedPurchaseID', null,
    'event-purchase-refund-' || :'claimedPurchaseID',
    'event-purchase-refund', 'stripe', 'processing',

    :'processingClaimID', current_timestamp
), (
    :'finalizedJobID', 4, :'finalizedPurchaseID',
    'provider refund failed: re_failed_123',
    'event-purchase-refund-' || :'finalizedPurchaseID',
    'event-purchase-refund', 'stripe', 'failed',

    null, null
), (
    :'invalidJobID', 4, :'invalidPurchaseID',
    'provider refund failed: re_invalid_123',
    'event-purchase-refund-' || :'invalidPurchaseID',
    'event-purchase-refund', 'stripe', 'failed',

    null, null
), (
    :'refundJobID', 3, :'purchaseID', 'prior provider retry',
    'event-purchase-refund-' || :'purchaseID',
    'event-purchase-refund', 'stripe', 'failed',

    null, null
), (
    :'terminalJobID', 5, :'terminalPurchaseID',
    'provider refund failed: re_terminal_123_refund_succeeded',
    'event-purchase-refund-' || :'terminalPurchaseID',
    'event-purchase-refund', 'stripe', 'failed',

    null, null
);

-- Provider records for claimed, pending, finalized, and invalid recovery scenarios
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status,
    terminal_failure,

    event_refund_request_id,
    finalized_at,
    provider_refund_id,
    provider_refunded_at
) values (
    :'claimedRefundID',
    2500,
    'USD',
    :'claimedPurchaseID',
    'automatic-unfulfillable-checkout',
    :'claimedJobID',
    'stripe',
    'provider-pending',
    false,

    null,
    null,
    null,
    null
), (
    :'finalizedRefundID',
    2500,
    'USD',
    :'finalizedPurchaseID',
    'automatic-unfulfillable-checkout',
    :'finalizedJobID',
    'stripe',
    'provider-failed',
    false,

    null,
    current_timestamp,
    null,
    null
), (
    :'invalidRefundID',
    2500,
    'USD',
    :'invalidPurchaseID',
    'automatic-unfulfillable-checkout',
    :'invalidJobID',
    'stripe',
    'provider-failed',
    false,

    null,
    current_timestamp,
    null,
    null
), (
    :'refundID',
    2500,
    'USD',
    :'purchaseID',
    'refund-request-approval',
    :'refundJobID',
    'stripe',
    'provider-pending',
    false,

    :'refundRequestID',
    null,
    null,
    null
), (
    :'terminalRefundID',
    2500,
    'USD',
    :'terminalPurchaseID',
    'automatic-unfulfillable-checkout',
    :'terminalJobID',
    'stripe',
    'provider-failed',
    true,

    null,
    null,
    're_terminal_123_refund_succeeded',
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
        're_success_123_refund_succeeded'
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
        're_success_123_refund_succeeded'
    ) - 'event_purchase_refund_id' - 'provider_refunded_at',
    jsonb_build_object(
        'amount_minor', 2500,
        'attempt_count', 0,
        'currency_code', 'USD',
        'event_purchase_id', :'purchaseID'::uuid,
        'idempotency_key', 'event-purchase-refund-' || :'purchaseID',
        'kind', 'refund-request-approval',
        'payment_job_id', :'refundJobID'::uuid,
        'payment_provider', 'stripe',
        'provider_refund_id', 're_success_123_refund_succeeded',
        'status', 'provider-succeeded',
        'terminal_failure', false
    ),
    'Should record provider refund success on a pending refund row'
);

-- Should allow retry with the same provider refund id
select is(
    record_event_purchase_refund_succeeded(
        :'refundID'::uuid,
        'event-purchase-refund-' || :'purchaseID',
        're_success_123_refund_succeeded'
    ) - 'event_purchase_refund_id' - 'provider_refunded_at',
    jsonb_build_object(
        'amount_minor', 2500,
        'attempt_count', 0,
        'currency_code', 'USD',
        'event_purchase_id', :'purchaseID'::uuid,
        'idempotency_key', 'event-purchase-refund-' || :'purchaseID',
        'kind', 'refund-request-approval',
        'payment_job_id', :'refundJobID'::uuid,
        'payment_provider', 'stripe',
        'provider_refund_id', 're_success_123_refund_succeeded',
        'status', 'provider-succeeded',
        'terminal_failure', false
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

-- Should reset the job for local finalization after provider success
select results_eq(
    format($$
        select attempt_count, failure_message, next_attempt_at <= current_timestamp, status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'refundJobID'),
    $$ values (0, null::text, true, 'pending'::text) $$,
    'Should reset the job for local finalization after provider success'
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
    $$ values ('re_success_123_refund_succeeded'::text, 'provider-succeeded'::text) $$,
    'Should ignore a successful result from a superseded attempt'
);

-- Should not revive a terminal provider refund with delayed success
select results_eq(
    format($$
        with delayed_success as materialized (
            select record_event_purchase_refund_succeeded(
                %L::uuid,
                %L,
                're_terminal_123_refund_succeeded'
            )
        )
        select pj.failure_message, epr.provider_refund_id, epr.status
        from event_purchase_refund epr
        join payment_job pj using (payment_job_id)
        cross join delayed_success
        where event_purchase_refund_id = %L::uuid
    $$,
        :'terminalRefundID',
        'event-purchase-refund-' || :'terminalPurchaseID',
        :'terminalRefundID'
    ),
    $$ values (
        'provider refund failed: re_terminal_123_refund_succeeded'::text,
        're_terminal_123_refund_succeeded'::text,
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
        select pj.failure_message, epr.provider_refund_id, epr.status, ep.status
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        join payment_job pj using (payment_job_id)
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
            pj.failure_message,
            epr.provider_refund_id,
            epr.provider_refunded_at is not null,
            pj.status,
            ep.status
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        join payment_job pj using (payment_job_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'finalizedRefundID'),
    $$ values (null::text, 're_recovery_123'::text, true, 'completed'::text, 'refunded'::text) $$,
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

-- Should reject provider success from a stale worker claim
select throws_ok(
    format($$select record_event_purchase_refund_succeeded(
        %L::uuid,
        %L,
        're_claimed_123',
        %L::uuid
    )$$,
        :'claimedRefundID',
        'event-purchase-refund-' || :'claimedPurchaseID',
        :'staleClaimID'
    ),
    'event purchase refund claim is stale',
    'Should reject provider success from a stale worker claim'
);

-- Should accept provider success from the current worker claim
select is(
    record_event_purchase_refund_succeeded(
        :'claimedRefundID'::uuid,
        'event-purchase-refund-' || :'claimedPurchaseID',
        're_claimed_123',
        :'processingClaimID'::uuid
    ) - 'event_purchase_refund_id' - 'provider_refunded_at',
    jsonb_build_object(
        'amount_minor', 2500,
        'attempt_count', 0,
        'claim_id', :'processingClaimID'::uuid,
        'currency_code', 'USD',
        'event_purchase_id', :'claimedPurchaseID'::uuid,
        'idempotency_key', 'event-purchase-refund-' || :'claimedPurchaseID',
        'kind', 'automatic-unfulfillable-checkout',
        'payment_job_id', :'claimedJobID'::uuid,
        'payment_provider', 'stripe',
        'provider_refund_id', 're_claimed_123',
        'status', 'provider-succeeded',
        'terminal_failure', false
    ),
    'Should accept provider success from the current worker claim'
);

-- Should preserve the claim while resetting local finalization attempts
select results_eq(
    format($$
        select attempt_count, claim_id, status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'claimedJobID'),
    format($$ values (0, %L::uuid, 'processing'::text) $$, :'processingClaimID'),
    'Should preserve the claim while resetting local finalization attempts'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
