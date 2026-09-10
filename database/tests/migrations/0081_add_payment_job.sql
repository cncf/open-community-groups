-- Tests upgrading schema-80 payment lifecycle state into payment_job rows.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(24);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set completedFeeID '81000000-0000-0000-0000-000000000061'
\set confirmedRefundID '81000000-0000-0000-0000-000000000031'
\set exhaustedCreditNoteID '81000000-0000-0000-0000-000000000051'
\set exhaustedRefundID '81000000-0000-0000-0000-000000000015'
\set finalizedFailedRefundID '81000000-0000-0000-0000-000000000035'
\set finalizedRefundID '81000000-0000-0000-0000-000000000019'
\set issuedCreditNoteID '81000000-0000-0000-0000-000000000050'
\set operatorID '81000000-0000-0000-0000-000000000008'
\set pendingCreditNoteID '81000000-0000-0000-0000-000000000052'
\set pendingFeeID '81000000-0000-0000-0000-000000000060'
\set pendingRefundID '81000000-0000-0000-0000-000000000011'
\set processingClaimID '81000000-0000-0000-0000-000000000090'
\set processingCreditNoteClaimID '81000000-0000-0000-0000-000000000091'
\set processingCreditNoteID '81000000-0000-0000-0000-000000000053'
\set processingFeeClaimID '81000000-0000-0000-0000-000000000092'
\set processingFeeID '81000000-0000-0000-0000-000000000063'
\set processingRefundID '81000000-0000-0000-0000-000000000013'
\set recoveredFeeID '81000000-0000-0000-0000-000000000062'
\set recoveredRefundID '81000000-0000-0000-0000-000000000021'
\set terminalRefundID '81000000-0000-0000-0000-000000000017'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should drop the lifecycle columns from the domain tables
select hasnt_column('event_purchase_refund', 'attempt_count');
select hasnt_column('event_purchase_refund', 'idempotency_key');
select hasnt_column('event_purchase_refund', 'recovery_completed_at');
select hasnt_column('event_purchase_credit_note', 'status');
select hasnt_column('event_purchase_application_fee_adjustment', 'status');

-- Should link every domain row to its own payment job
select is(
    (
        select count(*)::int
        from payment_job pj
        where exists (select 1 from event_purchase_refund where payment_job_id = pj.payment_job_id)
        or exists (select 1 from event_purchase_credit_note where payment_job_id = pj.payment_job_id)
        or exists (select 1 from event_purchase_application_fee_adjustment where payment_job_id = pj.payment_job_id)
    ),
    16,
    'Should link every domain row to its own payment job'
);

-- Should carry the refund idempotency key, provider and purchase onto the job
select results_eq(
    format($$
        select pj.event_purchase_id = epr.event_purchase_id, pj.idempotency_key, pj.kind, pj.payment_provider_id
        from event_purchase_refund epr
        join payment_job pj using (payment_job_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'pendingRefundID'),
    $$ values (true, 'payment-job-refund-pending'::text, 'event-purchase-refund'::text, 'stripe'::text) $$,
    'Should carry the refund idempotency key, provider and purchase onto the job'
);

-- Should keep a waiting refund pending with its attempt budget intact
select results_eq(
    format($$
        select epr.status, pj.status, pj.attempt_count, pj.next_attempt_at
        from event_purchase_refund epr
        join payment_job pj using (payment_job_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'pendingRefundID'),
    $$ values ('provider-pending'::text, 'pending'::text, 0, '2024-01-01 10:00:00+00'::timestamptz) $$,
    'Should keep a waiting refund pending with its attempt budget intact'
);

-- Should keep a processing claim on the job and record provider success on the refund
select results_eq(
    format($$
        select epr.status, pj.status, pj.attempt_count, pj.claim_id, pj.claimed_at
        from event_purchase_refund epr
        join payment_job pj using (payment_job_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'processingRefundID'),
    format($$ values ('provider-succeeded'::text, 'processing'::text, 0, %L::uuid, '2024-01-02 10:05:00+00'::timestamptz) $$, :'processingClaimID'),
    'Should keep a processing claim on the job and record provider success on the refund'
);

-- Should move an exhausted retryable failure onto a failed job
select results_eq(
    format($$
        select epr.status, epr.terminal_failure, pj.status, pj.attempt_count, pj.failure_message
        from event_purchase_refund epr
        join payment_job pj using (payment_job_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'exhaustedRefundID'),
    $$ values ('provider-pending'::text, false, 'failed'::text, 10, 'provider unavailable'::text) $$,
    'Should move an exhausted retryable failure onto a failed job'
);

-- Should park a terminal provider failure on a failed job
select results_eq(
    format($$
        select epr.status, epr.terminal_failure, pj.status, pj.attempt_count, pj.failure_message, pj.completed_at
        from event_purchase_refund epr
        join payment_job pj using (payment_job_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'terminalRefundID'),
    $$ values ('provider-failed'::text, true, 'failed'::text, 2, 'provider refund failed: re_terminal'::text, null::timestamptz) $$,
    'Should park a terminal provider failure on a failed job'
);

-- Should complete the job of a finalized refund at its finalization time
select results_eq(
    format($$
        select epr.status, pj.status, pj.attempt_count, pj.completed_at, pj.failure_message
        from event_purchase_refund epr
        join payment_job pj using (payment_job_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'finalizedRefundID'),
    $$ values ('finalized'::text, 'completed'::text, 1, '2024-01-04 11:00:00+00'::timestamptz, null::text) $$,
    'Should complete the job of a finalized refund at its finalization time'
);

-- Should complete a recovered refund with its operator evidence
select results_eq(
    format($$
        select epr.status, epr.terminal_failure, pj.status, pj.completed_at, pj.failure_message,
            pj.recovery_completed_at, pj.recovery_completed_by_user_id, pj.recovery_note, pj.recovery_reference
        from event_purchase_refund epr
        join payment_job pj using (payment_job_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'recoveredRefundID'),
    format($$ values (
        'provider-failed'::text, true, 'completed'::text, '2024-01-06 12:00:00+00'::timestamptz, null::text,
        '2024-01-06 12:00:00+00'::timestamptz, %L::uuid, 'Refunded by bank transfer'::text, 'BANK-1'::text
    ) $$, :'operatorID'),
    'Should complete a recovered refund with its operator evidence'
);

-- Should give a provider-confirmed refund awaiting finalization a fresh due budget
select results_eq(
    format($$
        select epr.status, pj.status, pj.attempt_count, pj.failure_message, pj.next_attempt_at <= current_timestamp
        from event_purchase_refund epr
        join payment_job pj using (payment_job_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'confirmedRefundID'),
    $$ values ('provider-succeeded'::text, 'pending'::text, 0, null::text, true) $$,
    'Should give a provider-confirmed refund awaiting finalization a fresh due budget'
);

-- Should keep a locally finalized non-terminal failure provider-failed
select results_eq(
    format($$
        select epr.status, epr.terminal_failure, epr.finalized_at, pj.status, pj.attempt_count, pj.failure_message
        from event_purchase_refund epr
        join payment_job pj using (payment_job_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'finalizedFailedRefundID'),
    $$ values ('provider-failed'::text, false, '2024-01-08 09:00:00+00'::timestamptz, 'failed'::text, 2, 'provider refund failed: re_finalized_failed'::text) $$,
    'Should keep a locally finalized non-terminal failure provider-failed'
);

-- Should complete the job of an issued credit note
select results_eq(
    format($$
        select epcn.provider_credit_note_id, pj.event_purchase_id = ep.event_purchase_id, pj.idempotency_key, pj.kind, pj.status, pj.attempt_count, pj.completed_at
        from event_purchase_credit_note epcn
        join payment_job pj using (payment_job_id)
        join event_purchase_refund epr using (event_purchase_refund_id)
        join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
        where epcn.event_purchase_credit_note_id = %L::uuid
    $$, :'issuedCreditNoteID'),
    $$ values ('cn_issued'::text, true, 'payment-job-credit-note-issued'::text, 'event-purchase-credit-note'::text, 'completed'::text, 1, '2024-01-04 11:30:00+00'::timestamptz) $$,
    'Should complete the job of an issued credit note'
);

-- Should keep an exhausted credit note failed with its diagnostics
select results_eq(
    format($$
        select epcn.provider_credit_note_id, pj.status, pj.attempt_count, pj.failure_message, pj.next_attempt_at
        from event_purchase_credit_note epcn
        join payment_job pj using (payment_job_id)
        where epcn.event_purchase_credit_note_id = %L::uuid
    $$, :'exhaustedCreditNoteID'),
    $$ values (null::text, 'failed'::text, 10, 'credit note unavailable'::text, '2099-01-01 00:00:00+00'::timestamptz) $$,
    'Should keep an exhausted credit note failed with its diagnostics'
);

-- Should keep a waiting credit note pending
select results_eq(
    format($$
        select pj.status, pj.attempt_count, pj.claim_id
        from event_purchase_credit_note epcn
        join payment_job pj using (payment_job_id)
        where epcn.event_purchase_credit_note_id = %L::uuid
    $$, :'pendingCreditNoteID'),
    $$ values ('pending'::text, 0, null::uuid) $$,
    'Should keep a waiting credit note pending'
);

-- Should keep a claimed credit note processing under its claim
select results_eq(
    format($$
        select pj.status, pj.attempt_count, pj.claim_id, pj.claimed_at
        from event_purchase_credit_note epcn
        join payment_job pj using (payment_job_id)
        where epcn.event_purchase_credit_note_id = %L::uuid
    $$, :'processingCreditNoteID'),
    format($$ values ('processing'::text, 2, %L::uuid, '2024-01-06 10:05:00+00'::timestamptz) $$, :'processingCreditNoteClaimID'),
    'Should keep a claimed credit note processing under its claim'
);

-- Should keep a waiting fee adjustment pending on the purchase provider
select results_eq(
    format($$
        select epafa.kind, pj.event_purchase_id = epafa.event_purchase_id, pj.idempotency_key, pj.kind, pj.payment_provider_id, pj.status, pj.attempt_count
        from event_purchase_application_fee_adjustment epafa
        join payment_job pj using (payment_job_id)
        where epafa.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'pendingFeeID'),
    $$ values ('tax-reconciliation'::text, true, 'payment-job-fee-pending'::text, 'event-purchase-application-fee-adjustment'::text, 'stripe'::text, 'pending'::text, 0) $$,
    'Should keep a waiting fee adjustment pending on the purchase provider'
);

-- Should complete the job of a completed fee adjustment
select results_eq(
    format($$
        select epafa.provider_application_fee_refund_id, pj.status, pj.attempt_count, pj.completed_at
        from event_purchase_application_fee_adjustment epafa
        join payment_job pj using (payment_job_id)
        where epafa.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'completedFeeID'),
    $$ values ('fr_completed'::text, 'completed'::text, 1, '2024-01-04 11:45:00+00'::timestamptz) $$,
    'Should complete the job of a completed fee adjustment'
);

-- Should complete a recovered fee adjustment with its operator evidence
select results_eq(
    format($$
        select epafa.provider_application_fee_refund_id, pj.status, pj.attempt_count, pj.completed_at,
            pj.recovery_completed_at, pj.recovery_completed_by_user_id, pj.recovery_note, pj.recovery_reference
        from event_purchase_application_fee_adjustment epafa
        join payment_job pj using (payment_job_id)
        where epafa.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'recoveredFeeID'),
    format($$ values (
        'fr_recovered'::text, 'completed'::text, 10, '2024-01-06 13:00:00+00'::timestamptz,
        '2024-01-06 13:00:00+00'::timestamptz, %L::uuid, 'Fee returned manually'::text, 'FEE-1'::text
    ) $$, :'operatorID'),
    'Should complete a recovered fee adjustment with its operator evidence'
);

-- Should keep a claimed fee adjustment processing under its claim
select results_eq(
    format($$
        select pj.status, pj.attempt_count, pj.claim_id, pj.claimed_at
        from event_purchase_application_fee_adjustment epafa
        join payment_job pj using (payment_job_id)
        where epafa.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'processingFeeID'),
    format($$ values ('processing'::text, 4, %L::uuid, '2024-01-02 10:06:00+00'::timestamptz) $$, :'processingFeeClaimID'),
    'Should keep a claimed fee adjustment processing under its claim'
);

-- Should leave the migrated pending refund claimable by the new worker
select is(
    (claim_payment_job('event-purchase-refund', 'stripe')->>'idempotency_key'),
    'payment-job-refund-pending',
    'Should leave the migrated pending refund claimable by the new worker'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
