-- Tests claiming durable payment jobs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set applicationBlockedAdjustmentID 'd4110000-0000-0000-0000-000000000001'
\set applicationBlockedJobID 'd4110000-0000-0000-0000-000000000002'
\set applicationBlockedPurchaseID 'd4110000-0000-0000-0000-000000000003'
\set applicationReadyAdjustmentID 'd4110000-0000-0000-0000-000000000004'
\set applicationReadyJobID 'd4110000-0000-0000-0000-000000000005'
\set applicationReadyPurchaseID 'd4110000-0000-0000-0000-000000000006'
\set communityID 'd4110000-0000-0000-0000-000000000007'
\set creditBlockedCreditNoteID 'd4110000-0000-0000-0000-000000000008'
\set creditBlockedJobID 'd4110000-0000-0000-0000-000000000009'
\set creditBlockedPurchaseID 'd4110000-0000-0000-0000-000000000010'
\set creditBlockedRefundID 'd4110000-0000-0000-0000-000000000011'
\set creditBlockedRefundJobID 'd4110000-0000-0000-0000-000000000012'
\set creditReadyCreditNoteID 'd4110000-0000-0000-0000-000000000013'
\set creditReadyJobID 'd4110000-0000-0000-0000-000000000014'
\set creditReadyPurchaseID 'd4110000-0000-0000-0000-000000000015'
\set creditReadyRefundID 'd4110000-0000-0000-0000-000000000016'
\set creditReadyRefundJobID 'd4110000-0000-0000-0000-000000000017'
\set eventCategoryID 'd4110000-0000-0000-0000-000000000018'
\set eventID 'd4110000-0000-0000-0000-000000000019'
\set groupCategoryID 'd4110000-0000-0000-0000-000000000020'
\set groupID 'd4110000-0000-0000-0000-000000000021'
\set refundCompletedJobID 'd4110000-0000-0000-0000-000000000022'
\set refundCompletedPurchaseID 'd4110000-0000-0000-0000-000000000023'
\set refundCompletedID 'd4110000-0000-0000-0000-000000000024'
\set refundExhaustedID 'd4110000-0000-0000-0000-000000000025'
\set refundExhaustedJobID 'd4110000-0000-0000-0000-000000000026'
\set refundExhaustedPurchaseID 'd4110000-0000-0000-0000-000000000027'
\set refundFirstID 'd4110000-0000-0000-0000-000000000028'
\set refundFirstJobID 'd4110000-0000-0000-0000-000000000029'
\set refundFirstPurchaseID 'd4110000-0000-0000-0000-000000000030'
\set refundFutureID 'd4110000-0000-0000-0000-000000000031'
\set refundFutureJobID 'd4110000-0000-0000-0000-000000000032'
\set refundFuturePurchaseID 'd4110000-0000-0000-0000-000000000033'
\set refundOtherProviderID 'd4110000-0000-0000-0000-000000000034'
\set refundOtherProviderJobID 'd4110000-0000-0000-0000-000000000035'
\set refundOtherProviderPurchaseID 'd4110000-0000-0000-0000-000000000036'
\set refundProcessingClaimID 'd4110000-0000-0000-0000-000000000037'
\set refundProcessingID 'd4110000-0000-0000-0000-000000000038'
\set refundProcessingJobID 'd4110000-0000-0000-0000-000000000039'
\set refundProcessingPurchaseID 'd4110000-0000-0000-0000-000000000040'
\set refundSecondID 'd4110000-0000-0000-0000-000000000041'
\set refundSecondJobID 'd4110000-0000-0000-0000-000000000042'
\set refundSecondPurchaseID 'd4110000-0000-0000-0000-000000000043'
\set refundTerminalID 'd4110000-0000-0000-0000-000000000044'
\set refundTerminalJobID 'd4110000-0000-0000-0000-000000000045'
\set refundTerminalPurchaseID 'd4110000-0000-0000-0000-000000000046'
\set refundThirdID 'd4110000-0000-0000-0000-000000000047'
\set refundThirdJobID 'd4110000-0000-0000-0000-000000000048'
\set refundThirdPurchaseID 'd4110000-0000-0000-0000-000000000049'
\set ticketTypeID 'd4110000-0000-0000-0000-000000000050'
\set userID 'd4110000-0000-0000-0000-000000000051'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Additional provider used to verify provider-scoped claims
insert into payment_provider (display_name, payment_provider_id)
values ('Claim Payment Job Other Provider', 'claim-payment-job-other-d4110000');

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with every claim scenario
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by every claim purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General admission'
));

-- Purchases backing due, excluded, and provider-complete payment jobs
insert into event_purchase (
    amount_minor, charge_model, completed_at, connected_seller_id,
    currency_code, event_id, event_purchase_id, event_ticket_type_id,
    final_platform_fee_amount_minor, payment_provider_id,
    provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_invoice_id,
    provider_object_account_id, provider_payment_reference,
    provider_total_minor, provisional_platform_fee_amount_minor,
    seller_snapshot, status, subtotal_excluding_tax_minor, tax_amount_minor,
    tax_behavior, tax_calculation_mode, tax_classification, ticket_title,
    user_id, venue_snapshot
)
select
    2500,
    'direct-charge',
    current_timestamp,
    fixture.connected_seller_id,
    'USD',
    :'eventID',
    fixture.event_purchase_id,
    :'ticketTypeID',
    80,
    fixture.payment_provider_id,
    fixture.provider_application_fee_id,
    'ch_' || fixture.provider_reference,
    'cs_' || fixture.provider_reference,
    fixture.provider_invoice_id,
    fixture.connected_seller_id,
    'pi_' || fixture.provider_reference,
    2500,
    100,
    jsonb_build_object('display_name', 'Sponsor'),
    fixture.status,
    2300,
    200,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'userID',
    '{}'::jsonb
from (values
    (:'applicationBlockedPurchaseID'::uuid, 'refunded', 'stripe', 'acct_claim', null::text, 'in_application_blocked_d4110000', 'application_blocked_d4110000'),
    (:'applicationReadyPurchaseID'::uuid, 'refunded', 'stripe', 'acct_claim', 'fee_application_ready_d4110000', 'in_application_ready_d4110000', 'application_ready_d4110000'),
    (:'creditBlockedPurchaseID'::uuid, 'refunded', 'stripe', 'acct_claim', 'fee_credit_blocked_d4110000', 'in_credit_blocked_d4110000', 'credit_blocked_d4110000'),
    (:'creditReadyPurchaseID'::uuid, 'refunded', 'stripe', 'acct_claim', 'fee_credit_ready_d4110000', 'in_credit_ready_d4110000', 'credit_ready_d4110000'),
    (:'refundCompletedPurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_claim', 'fee_refund_completed_d4110000', 'in_refund_completed_d4110000', 'refund_completed_d4110000'),
    (:'refundExhaustedPurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_claim', 'fee_refund_exhausted_d4110000', 'in_refund_exhausted_d4110000', 'refund_exhausted_d4110000'),
    (:'refundFirstPurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_claim', 'fee_refund_first_d4110000', 'in_refund_first_d4110000', 'refund_first_d4110000'),
    (:'refundFuturePurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_claim', 'fee_refund_future_d4110000', 'in_refund_future_d4110000', 'refund_future_d4110000'),
    (:'refundOtherProviderPurchaseID'::uuid, 'refund-pending', 'claim-payment-job-other-d4110000', 'acct_other_claim', 'fee_refund_other_d4110000', 'in_refund_other_d4110000', 'refund_other_d4110000'),
    (:'refundProcessingPurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_claim', 'fee_refund_processing_d4110000', 'in_refund_processing_d4110000', 'refund_processing_d4110000'),
    (:'refundSecondPurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_claim', 'fee_refund_second_d4110000', 'in_refund_second_d4110000', 'refund_second_d4110000'),
    (:'refundTerminalPurchaseID'::uuid, 'refund-recovery-pending', 'stripe', 'acct_claim', 'fee_refund_terminal_d4110000', 'in_refund_terminal_d4110000', 'refund_terminal_d4110000'),
    (:'refundThirdPurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_claim', 'fee_refund_third_d4110000', 'in_refund_third_d4110000', 'refund_third_d4110000')
) as fixture (
    event_purchase_id,
    status,
    payment_provider_id,
    connected_seller_id,
    provider_application_fee_id,
    provider_invoice_id,
    provider_reference
);

-- Application-fee payment job blocked by missing provider fee context
insert into payment_job (
    created_at, event_purchase_id, idempotency_key, kind, next_attempt_at,
    payment_job_id, payment_provider_id
) values (
    '2024-01-01 00:00:00+00', :'applicationBlockedPurchaseID',
    'claim-payment-job-application-blocked-d4110000',
    'event-purchase-application-fee-adjustment', '2024-01-01 00:00:00+00',
    :'applicationBlockedJobID', 'stripe'
);

-- Application-fee payment job ready to claim
insert into payment_job (
    created_at, event_purchase_id, idempotency_key, kind, next_attempt_at,
    payment_job_id, payment_provider_id
) values (
    '2024-01-02 00:00:00+00', :'applicationReadyPurchaseID',
    'claim-payment-job-application-ready-d4110000',
    'event-purchase-application-fee-adjustment', '2024-01-02 00:00:00+00',
    :'applicationReadyJobID', 'stripe'
);

-- Credit-note payment job blocked by an unconfirmed refund
insert into payment_job (
    created_at, event_purchase_id, idempotency_key, kind, next_attempt_at,
    payment_job_id, payment_provider_id
) values (
    '2024-01-01 00:00:00+00', :'creditBlockedPurchaseID',
    'claim-payment-job-credit-blocked-d4110000',
    'event-purchase-credit-note', '2024-01-01 00:00:00+00',
    :'creditBlockedJobID', 'stripe'
);

-- Refund payment job behind the blocked credit note
insert into payment_job (
    completed_at, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id, status
) values (
    current_timestamp, :'creditBlockedPurchaseID',
    'claim-payment-job-credit-blocked-refund-d4110000',
    'event-purchase-refund', :'creditBlockedRefundJobID', 'stripe',
    'completed'
);

-- Failed credit-note payment job ready to claim
insert into payment_job (
    attempt_count, created_at, event_purchase_id, failure_message,
    idempotency_key, kind, next_attempt_at, payment_job_id,
    payment_provider_id, status
) values (
    2, '2024-01-02 00:00:00+00', :'creditReadyPurchaseID',
    'provider unavailable', 'claim-payment-job-credit-ready-d4110000',
    'event-purchase-credit-note', '2024-01-02 00:00:00+00',
    :'creditReadyJobID', 'stripe', 'failed'
);

-- Refund payment job behind the ready credit note
insert into payment_job (
    completed_at, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id, status
) values (
    current_timestamp, :'creditReadyPurchaseID',
    'claim-payment-job-credit-ready-refund-d4110000',
    'event-purchase-refund', :'creditReadyRefundJobID', 'stripe',
    'completed'
);

-- Completed refund payment job skipped by claims
insert into payment_job (
    completed_at, event_purchase_id, idempotency_key, kind, next_attempt_at,
    payment_job_id, payment_provider_id, status
) values (
    current_timestamp, :'refundCompletedPurchaseID',
    'claim-payment-job-refund-completed-d4110000', 'event-purchase-refund',
    '2024-01-01 00:00:00+00', :'refundCompletedJobID', 'stripe',
    'completed'
);

-- Exhausted refund payment job skipped by claims
insert into payment_job (
    attempt_count, created_at, event_purchase_id, failure_message,
    idempotency_key, kind, next_attempt_at, payment_job_id,
    payment_provider_id, status
) values (
    10, '2024-01-01 00:00:00+00', :'refundExhaustedPurchaseID',
    'automatic attempts exhausted', 'claim-payment-job-refund-exhausted-d4110000',
    'event-purchase-refund', '2024-01-01 00:00:00+00',
    :'refundExhaustedJobID', 'stripe', 'failed'
);

-- Due refund payment job ordered first by next attempt time
insert into payment_job (
    created_at, event_purchase_id, idempotency_key, kind, next_attempt_at,
    payment_job_id, payment_provider_id
) values (
    '2024-01-03 00:00:00+00', :'refundFirstPurchaseID',
    'claim-payment-job-refund-first-d4110000', 'event-purchase-refund',
    '2024-01-01 00:00:00+00', :'refundFirstJobID', 'stripe'
);

-- Future refund payment job skipped by claims
insert into payment_job (
    created_at, event_purchase_id, idempotency_key, kind, next_attempt_at,
    payment_job_id, payment_provider_id
) values (
    '2024-01-01 00:00:00+00', :'refundFuturePurchaseID',
    'claim-payment-job-refund-future-d4110000', 'event-purchase-refund',
    '2099-01-01 00:00:00+00', :'refundFutureJobID', 'stripe'
);

-- Other-provider refund payment job skipped by stripe claims
insert into payment_job (
    created_at, event_purchase_id, idempotency_key, kind, next_attempt_at,
    payment_job_id, payment_provider_id
) values (
    '2024-01-01 00:00:00+00', :'refundOtherProviderPurchaseID',
    'claim-payment-job-refund-other-provider-d4110000',
    'event-purchase-refund', '2024-01-01 00:00:00+00',
    :'refundOtherProviderJobID', 'claim-payment-job-other-d4110000'
);

-- Processing refund payment job skipped by claims
insert into payment_job (
    attempt_count, claim_id, claimed_at, created_at, event_purchase_id,
    idempotency_key, kind, next_attempt_at, payment_job_id,
    payment_provider_id, status
) values (
    1, :'refundProcessingClaimID', current_timestamp,
    '2024-01-01 00:00:00+00', :'refundProcessingPurchaseID',
    'claim-payment-job-refund-processing-d4110000', 'event-purchase-refund',
    '2024-01-01 00:00:00+00', :'refundProcessingJobID', 'stripe',
    'processing'
);

-- Due refund payment job ordered second by created time
insert into payment_job (
    created_at, event_purchase_id, idempotency_key, kind, next_attempt_at,
    payment_job_id, payment_provider_id
) values (
    '2024-01-01 00:00:00+00', :'refundSecondPurchaseID',
    'claim-payment-job-refund-second-d4110000', 'event-purchase-refund',
    '2024-01-02 00:00:00+00', :'refundSecondJobID', 'stripe'
);

-- Terminal refund payment job skipped by readiness
insert into payment_job (
    attempt_count, created_at, event_purchase_id, failure_message,
    idempotency_key, kind, next_attempt_at, payment_job_id,
    payment_provider_id, status
) values (
    1, '2024-01-01 00:00:00+00', :'refundTerminalPurchaseID',
    'terminal failure', 'claim-payment-job-refund-terminal-d4110000',
    'event-purchase-refund', '2024-01-01 00:00:00+00',
    :'refundTerminalJobID', 'stripe', 'failed'
);

-- Due refund payment job ordered third by created time
insert into payment_job (
    created_at, event_purchase_id, idempotency_key, kind, next_attempt_at,
    payment_job_id, payment_provider_id
) values (
    '2024-01-04 00:00:00+00', :'refundThirdPurchaseID',
    'claim-payment-job-refund-third-d4110000', 'event-purchase-refund',
    '2024-01-02 00:00:00+00', :'refundThirdJobID', 'stripe'
);

-- Provider-unconfirmed refund behind the blocked credit note
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, status, terminal_failure
) values (
    2500, 'USD', :'creditBlockedPurchaseID', :'creditBlockedRefundID',
    current_timestamp, 'event-cancellation', :'creditBlockedRefundJobID',
    'stripe', 're_credit_blocked_d4110000', 'provider-failed', false
);

-- Provider-confirmed refund behind the ready credit note
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, provider_refunded_at, status, terminal_failure
) values (
    2500, 'USD', :'creditReadyPurchaseID', :'creditReadyRefundID',
    current_timestamp, 'event-cancellation', :'creditReadyRefundJobID',
    'stripe', 're_credit_ready_d4110000', current_timestamp, 'finalized',
    false
);

-- Finalized refund whose completed job must stay unclaimed
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, provider_refunded_at, status, terminal_failure
) values (
    2500, 'USD', :'refundCompletedPurchaseID', :'refundCompletedID',
    current_timestamp, 'event-cancellation', :'refundCompletedJobID',
    'stripe', 're_refund_completed_d4110000', current_timestamp, 'finalized',
    false
);

-- Refund domain rows covering scheduling, attempts, provider scoping and states
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, status, terminal_failure,
    provider_refund_id
) values
    (2500, 'USD', :'refundExhaustedPurchaseID', :'refundExhaustedID', 'event-cancellation', :'refundExhaustedJobID', 'stripe', 'provider-pending', false, null),
    (2500, 'USD', :'refundFirstPurchaseID', :'refundFirstID', 'event-cancellation', :'refundFirstJobID', 'stripe', 'provider-pending', false, null),
    (2500, 'USD', :'refundFuturePurchaseID', :'refundFutureID', 'event-cancellation', :'refundFutureJobID', 'stripe', 'provider-pending', false, null),
    (2500, 'USD', :'refundOtherProviderPurchaseID', :'refundOtherProviderID', 'event-cancellation', :'refundOtherProviderJobID', 'claim-payment-job-other-d4110000', 'provider-pending', false, null),
    (2500, 'USD', :'refundProcessingPurchaseID', :'refundProcessingID', 'event-cancellation', :'refundProcessingJobID', 'stripe', 'provider-pending', false, null),
    (2500, 'USD', :'refundSecondPurchaseID', :'refundSecondID', 'event-cancellation', :'refundSecondJobID', 'stripe', 'provider-pending', false, null),
    (2500, 'USD', :'refundTerminalPurchaseID', :'refundTerminalID', 'event-cancellation', :'refundTerminalJobID', 'stripe', 'provider-failed', true, 're_terminal_d4110000'),
    (2500, 'USD', :'refundThirdPurchaseID', :'refundThirdID', 'event-cancellation', :'refundThirdJobID', 'stripe', 'provider-pending', false, null);

-- Application-fee adjustment waiting for provider fee context
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id
) values (
    20, :'applicationBlockedAdjustmentID', :'applicationBlockedPurchaseID',
    'tax-reconciliation', :'applicationBlockedJobID'
);

-- Application-fee adjustment ready to claim
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id
) values (
    20, :'applicationReadyAdjustmentID', :'applicationReadyPurchaseID',
    'tax-reconciliation', :'applicationReadyJobID'
);

-- Credit note waiting for its refund provider outcome
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'creditBlockedCreditNoteID', :'creditBlockedRefundID',
    :'creditBlockedJobID', 'stripe', 'acct_claim', 200
);

-- Credit note ready to claim
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'creditReadyCreditNoteID', :'creditReadyRefundID',
    :'creditReadyJobID', 'stripe', 'acct_claim', 200
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should claim application-fee work with nested provider context
select results_eq(
    format($$
        with claimed as (
            select claim_payment_job(
                'event-purchase-application-fee-adjustment',
                'stripe'
            ) as item
        )
        select
            item ? 'claim_id',
            item - 'claim_id'
        from claimed
    $$),
    format($$ values (
        true,
        jsonb_build_object(
            'attempt_count', 1,
            'application_fee_adjustment', jsonb_build_object(
                'amount_minor', 20,
                'connected_seller_id', 'acct_claim',
                'currency_code', 'USD',
                'event_purchase_application_fee_adjustment_id', %L::uuid,
                'kind', 'tax-reconciliation',
                'provider_application_fee_id', 'fee_application_ready_d4110000'
            ),
            'event_purchase_id', %L::uuid,
            'idempotency_key', 'claim-payment-job-application-ready-d4110000',
            'kind', 'event-purchase-application-fee-adjustment',
            'payment_job_id', %L::uuid,
            'payment_provider', 'stripe',
            'status', 'processing'
        )
    ) $$, :'applicationReadyAdjustmentID', :'applicationReadyPurchaseID', :'applicationReadyJobID'),
    'Should claim application-fee work with nested provider context'
);

-- Should claim credit-note work with nested provider context
select results_eq(
    format($$
        with claimed as (
            select claim_payment_job('event-purchase-credit-note', 'stripe') as item
        )
        select
            item ? 'claim_id',
            item - 'claim_id'
        from claimed
    $$),
    format($$ values (
        true,
        jsonb_build_object(
            'attempt_count', 3,
            'credit_note', jsonb_build_object(
                'amount_minor', 2500,
                'connected_seller_id', 'acct_claim',
                'event_purchase_credit_note_id', %L::uuid,
                'event_purchase_refund_id', %L::uuid,
                'provider_invoice_id', 'in_credit_ready_d4110000',
                'provider_refund_id', 're_credit_ready_d4110000',
                'tax_amount_minor', 200
            ),
            'event_purchase_id', %L::uuid,
            'failure_message', 'provider unavailable',
            'idempotency_key', 'claim-payment-job-credit-ready-d4110000',
            'kind', 'event-purchase-credit-note',
            'payment_job_id', %L::uuid,
            'payment_provider', 'stripe',
            'status', 'processing'
        )
    ) $$, :'creditReadyCreditNoteID', :'creditReadyRefundID', :'creditReadyPurchaseID', :'creditReadyJobID'),
    'Should claim credit-note work with nested provider context'
);

-- Should claim refund work with nested notification context
select results_eq(
    format($$
        with claimed as (
            select claim_payment_job('event-purchase-refund', 'stripe') as item
        )
        select
            item ? 'claim_id',
            jsonb_set(
                item - 'claim_id',
                '{refund}',
                (item->'refund') - 'claim_id'
            )
        from claimed
    $$),
    format($$ values (
        true,
        jsonb_build_object(
            'attempt_count', 1,
            'event_purchase_id', %L::uuid,
            'idempotency_key', 'claim-payment-job-refund-first-d4110000',
            'kind', 'event-purchase-refund',
            'payment_job_id', %L::uuid,
            'payment_provider', 'stripe',
            'refund', jsonb_build_object(
                'amount_minor', 2500,
                'attempt_count', 1,
                'community_id', %L::uuid,
                'connected_seller_id', 'acct_claim',
                'currency_code', 'USD',
                'event_id', %L::uuid,
                'event_purchase_id', %L::uuid,
                'event_purchase_refund_id', %L::uuid,
                'idempotency_key', 'claim-payment-job-refund-first-d4110000',
                'kind', 'event-cancellation',
                'payment_job_id', %L::uuid,
                'payment_provider', 'stripe',
                'provider_payment_reference', 'pi_refund_first_d4110000',
                'status', 'provider-pending',
                'terminal_failure', false
            ),
            'status', 'processing'
        )
    ) $$,
        :'refundFirstPurchaseID',
        :'refundFirstJobID',
        :'communityID',
        :'eventID',
        :'refundFirstPurchaseID',
        :'refundFirstID',
        :'refundFirstJobID'
    ),
    'Should claim refund work with nested notification context'
);

-- Should persist claimed payment job pins
select results_eq(
    format($$
        select payment_job_id, attempt_count, claim_id is not null, status
        from payment_job
        where payment_job_id in (%L::uuid, %L::uuid, %L::uuid)
        order by payment_job_id
    $$, :'applicationReadyJobID', :'creditReadyJobID', :'refundFirstJobID'),
    format($$ values
        (%L::uuid, 1, true, 'processing'::text),
        (%L::uuid, 3, true, 'processing'::text),
        (%L::uuid, 1, true, 'processing'::text)
    $$, :'applicationReadyJobID', :'creditReadyJobID', :'refundFirstJobID'),
    'Should persist claimed payment job pins'
);

-- Should order refund jobs by next attempt before created time
select is(
    (claim_payment_job('event-purchase-refund', 'stripe')->>'payment_job_id')::uuid,
    :'refundSecondJobID'::uuid,
    'Should order refund jobs by next attempt before created time'
);

-- Should order refund jobs with the same next attempt by created time
select is(
    (claim_payment_job('event-purchase-refund', 'stripe')->>'payment_job_id')::uuid,
    :'refundThirdJobID'::uuid,
    'Should order refund jobs with the same next attempt by created time'
);

-- Should return null when no eligible provider-scoped jobs remain
select is(
    claim_payment_job('event-purchase-refund', 'stripe'),
    null,
    'Should return null when no eligible provider-scoped jobs remain'
);

-- Should claim only work scoped to the requested provider
select is(
    (claim_payment_job(
        'event-purchase-refund',
        'claim-payment-job-other-d4110000'
    )->>'payment_job_id')::uuid,
    :'refundOtherProviderJobID'::uuid,
    'Should claim only work scoped to the requested provider'
);

-- Should leave ineligible payment jobs unclaimed
select results_eq(
    format($$
        select payment_job_id, attempt_count, claim_id, status
        from payment_job
        where payment_job_id in (
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid
        )
        order by payment_job_id
    $$,
        :'applicationBlockedJobID',
        :'creditBlockedJobID',
        :'refundCompletedJobID',
        :'refundExhaustedJobID',
        :'refundFutureJobID',
        :'refundProcessingJobID',
        :'refundTerminalJobID'
    ),
    format($$ values
        (%L::uuid, 0, null::uuid, 'pending'::text),
        (%L::uuid, 0, null::uuid, 'pending'::text),
        (%L::uuid, 0, null::uuid, 'completed'::text),
        (%L::uuid, 10, null::uuid, 'failed'::text),
        (%L::uuid, 0, null::uuid, 'pending'::text),
        (%L::uuid, 1, %L::uuid, 'processing'::text),
        (%L::uuid, 1, null::uuid, 'failed'::text)
    $$,
        :'applicationBlockedJobID',
        :'creditBlockedJobID',
        :'refundCompletedJobID',
        :'refundExhaustedJobID',
        :'refundFutureJobID',
        :'refundProcessingJobID',
        :'refundProcessingClaimID',
        :'refundTerminalJobID'
    ),
    'Should leave ineligible payment jobs unclaimed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
