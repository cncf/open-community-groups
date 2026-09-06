-- Tests enforcing provider outcomes on domain rows of completed payment jobs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd4170000-0000-0000-0000-000000000001'
\set creditAcceptJobID 'd4170000-0000-0000-0000-000000000002'
\set creditAcceptNoteID 'd4170000-0000-0000-0000-000000000003'
\set creditAcceptPurchaseID 'd4170000-0000-0000-0000-000000000004'
\set creditAcceptRefundID 'd4170000-0000-0000-0000-000000000005'
\set creditAcceptRefundJobID 'd4170000-0000-0000-0000-000000000006'
\set creditClearJobID 'd4170000-0000-0000-0000-000000000007'
\set creditClearNoteID 'd4170000-0000-0000-0000-000000000008'
\set creditClearPurchaseID 'd4170000-0000-0000-0000-000000000009'
\set creditClearRefundID 'd4170000-0000-0000-0000-000000000010'
\set creditClearRefundJobID 'd4170000-0000-0000-0000-000000000011'
\set eventCategoryID 'd4170000-0000-0000-0000-000000000012'
\set eventID 'd4170000-0000-0000-0000-000000000013'
\set feeAcceptAdjustmentID 'd4170000-0000-0000-0000-000000000014'
\set feeAcceptJobID 'd4170000-0000-0000-0000-000000000015'
\set feeAcceptPurchaseID 'd4170000-0000-0000-0000-000000000016'
\set feeClearAdjustmentID 'd4170000-0000-0000-0000-000000000017'
\set feeClearJobID 'd4170000-0000-0000-0000-000000000018'
\set feeClearPurchaseID 'd4170000-0000-0000-0000-000000000019'
\set groupCategoryID 'd4170000-0000-0000-0000-000000000020'
\set groupID 'd4170000-0000-0000-0000-000000000021'
\set pendingJobID 'd4170000-0000-0000-0000-000000000022'
\set pendingPurchaseID 'd4170000-0000-0000-0000-000000000023'
\set pendingRefundID 'd4170000-0000-0000-0000-000000000024'
\set refundAcceptID 'd4170000-0000-0000-0000-000000000025'
\set refundAcceptJobID 'd4170000-0000-0000-0000-000000000026'
\set refundAcceptPurchaseID 'd4170000-0000-0000-0000-000000000027'
\set refundClearID 'd4170000-0000-0000-0000-000000000028'
\set refundClearJobID 'd4170000-0000-0000-0000-000000000029'
\set refundClearPurchaseID 'd4170000-0000-0000-0000-000000000030'
\set ticketTypeID 'd4170000-0000-0000-0000-000000000031'
\set userID 'd4170000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning every purchase behind the outcome checks
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by every purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 20,
    'title', 'General admission'
));

-- Direct-charge purchases owning one domain row per scenario
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
    2500, 'direct-charge', current_timestamp, 'acct_d417', 'USD', :'eventID',
    fixture.event_purchase_id, :'ticketTypeID', 80, 'stripe',
    'fee_' || fixture.reference, 'ch_' || fixture.reference,
    'cs_' || fixture.reference, 'in_' || fixture.reference, 'acct_d417',
    'pi_' || fixture.reference, 2500, 100,
    '{"display_name":"Sponsor"}'::jsonb, fixture.status, 2300, 200,
    'inclusive', 'manual', 'professional-event-admission',
    'General admission', :'userID', '{}'::jsonb
from (values
    (:'creditAcceptPurchaseID'::uuid, 'refunded', 'credit_accept_d4170000'),
    (:'creditClearPurchaseID'::uuid, 'refunded', 'credit_clear_d4170000'),
    (:'feeAcceptPurchaseID'::uuid, 'refunded', 'fee_accept_d4170000'),
    (:'feeClearPurchaseID'::uuid, 'refunded', 'fee_clear_d4170000'),
    (:'pendingPurchaseID'::uuid, 'refund-pending', 'pending_d4170000'),
    (:'refundAcceptPurchaseID'::uuid, 'refunded', 'refund_accept_d4170000'),
    (:'refundClearPurchaseID'::uuid, 'refunded', 'refund_clear_d4170000')
) as fixture(event_purchase_id, status, reference);

-- Completed jobs whose domain rows are inserted by the accepted scenarios
insert into payment_job (
    completed_at, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id, status
) values
    (current_timestamp, :'creditAcceptPurchaseID', 'check-payment-job-domain-credit-accept-d4170000', 'event-purchase-credit-note', :'creditAcceptJobID', 'stripe', 'completed'),
    (current_timestamp, :'creditAcceptPurchaseID', 'check-payment-job-domain-credit-accept-refund-d4170000', 'event-purchase-refund', :'creditAcceptRefundJobID', 'stripe', 'completed'),
    (current_timestamp, :'feeAcceptPurchaseID', 'check-payment-job-domain-fee-accept-d4170000', 'event-purchase-application-fee-adjustment', :'feeAcceptJobID', 'stripe', 'completed'),
    (current_timestamp, :'refundAcceptPurchaseID', 'check-payment-job-domain-refund-accept-d4170000', 'event-purchase-refund', :'refundAcceptJobID', 'stripe', 'completed');

-- Completed jobs whose seeded domain rows lose their outcome in the rejected updates
insert into payment_job (
    completed_at, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id, status
) values
    (current_timestamp, :'creditClearPurchaseID', 'check-payment-job-domain-credit-clear-d4170000', 'event-purchase-credit-note', :'creditClearJobID', 'stripe', 'completed'),
    (current_timestamp, :'creditClearPurchaseID', 'check-payment-job-domain-credit-clear-refund-d4170000', 'event-purchase-refund', :'creditClearRefundJobID', 'stripe', 'completed'),
    (current_timestamp, :'feeClearPurchaseID', 'check-payment-job-domain-fee-clear-d4170000', 'event-purchase-application-fee-adjustment', :'feeClearJobID', 'stripe', 'completed'),
    (current_timestamp, :'refundClearPurchaseID', 'check-payment-job-domain-refund-clear-d4170000', 'event-purchase-refund', :'refundClearJobID', 'stripe', 'completed');

-- Pending refund job whose domain row may lack an outcome
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'pendingPurchaseID', 'check-payment-job-domain-pending-d4170000',
    'event-purchase-refund', :'pendingJobID', 'stripe'
);

-- Fee adjustment with its outcome behind a completed job
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id,
    provider_application_fee_refund_id
) values (
    80, :'feeClearAdjustmentID', :'feeClearPurchaseID', 'purchase-refund',
    :'feeClearJobID', 'fr_clear_d4170000'
);

-- Finalized refunds behind the credit notes of the accepted and rejected scenarios
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, provider_refunded_at, status, terminal_failure
) values
    (2500, 'USD', :'creditAcceptPurchaseID', :'creditAcceptRefundID', current_timestamp, 'event-cancellation', :'creditAcceptRefundJobID', 'stripe', 're_credit_accept_d4170000', current_timestamp, 'finalized', false),
    (2500, 'USD', :'creditClearPurchaseID', :'creditClearRefundID', current_timestamp, 'event-cancellation', :'creditClearRefundJobID', 'stripe', 're_credit_clear_d4170000', current_timestamp, 'finalized', false);

-- Finalized refund whose outcome the rejected update clears
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, provider_refunded_at, status, terminal_failure
) values (
    2500, 'USD', :'refundClearPurchaseID', :'refundClearID',
    current_timestamp, 'event-cancellation', :'refundClearJobID', 'stripe',
    're_refund_clear_d4170000', current_timestamp, 'finalized', false
);

-- Credit note with its outcome behind a completed job
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_credit_note_id, provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'creditClearNoteID', :'creditClearRefundID',
    :'creditClearJobID', 'stripe', 'cn_clear_d4170000', 'acct_d417', 200
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a credit note with its outcome behind a completed job
select lives_ok(
    format(
        $$insert into event_purchase_credit_note (amount_minor, currency_code, event_purchase_credit_note_id, event_purchase_refund_id, payment_job_id, payment_provider_id, provider_credit_note_id, provider_object_account_id, tax_amount_minor)
        values (2500, 'USD', %L::uuid, %L::uuid, %L::uuid, 'stripe', 'cn_accept_d4170000', 'acct_d417', 200)$$,
        :'creditAcceptNoteID', :'creditAcceptRefundID', :'creditAcceptJobID'
    ),
    'Should accept a credit note with its outcome behind a completed job'
);

-- Should accept a fee adjustment with its outcome behind a completed job
select lives_ok(
    format(
        $$insert into event_purchase_application_fee_adjustment (amount_minor, event_purchase_application_fee_adjustment_id, event_purchase_id, kind, payment_job_id, provider_application_fee_refund_id)
        values (80, %L::uuid, %L::uuid, 'purchase-refund', %L::uuid, 'fr_accept_d4170000')$$,
        :'feeAcceptAdjustmentID', :'feeAcceptPurchaseID', :'feeAcceptJobID'
    ),
    'Should accept a fee adjustment with its outcome behind a completed job'
);

-- Should accept a finalized refund behind a completed job
select lives_ok(
    format(
        $$insert into event_purchase_refund (amount_minor, currency_code, event_purchase_id, event_purchase_refund_id, finalized_at, kind, payment_job_id, payment_provider_id, provider_refund_id, provider_refunded_at, status, terminal_failure)
        values (2500, 'USD', %L::uuid, %L::uuid, current_timestamp, 'event-cancellation', %L::uuid, 'stripe', 're_refund_accept_d4170000', current_timestamp, 'finalized', false)$$,
        :'refundAcceptPurchaseID', :'refundAcceptID', :'refundAcceptJobID'
    ),
    'Should accept a finalized refund behind a completed job'
);

-- Should accept a refund without an outcome behind a pending job
select lives_ok(
    format(
        $$insert into event_purchase_refund (amount_minor, currency_code, event_purchase_id, event_purchase_refund_id, kind, payment_job_id, payment_provider_id, status, terminal_failure)
        values (2500, 'USD', %L::uuid, %L::uuid, 'event-cancellation', %L::uuid, 'stripe', 'provider-pending', false)$$,
        :'pendingPurchaseID', :'pendingRefundID', :'pendingJobID'
    ),
    'Should accept a refund without an outcome behind a pending job'
);

-- Should reject clearing the outcome of a completed credit note
select throws_ok(
    format(
        $$update event_purchase_credit_note set provider_credit_note_id = null where event_purchase_credit_note_id = %L::uuid$$,
        :'creditClearNoteID'
    ),
    'payment job completed without its provider outcome',
    'Should reject clearing the outcome of a completed credit note'
);

-- Should reject clearing the outcome of a completed fee adjustment
select throws_ok(
    format(
        $$update event_purchase_application_fee_adjustment set provider_application_fee_refund_id = null where event_purchase_application_fee_adjustment_id = %L::uuid$$,
        :'feeClearAdjustmentID'
    ),
    'payment job completed without its provider outcome',
    'Should reject clearing the outcome of a completed fee adjustment'
);

-- Should reject clearing the finalization of a completed refund
select throws_ok(
    format(
        $$update event_purchase_refund set finalized_at = null, status = 'provider-succeeded' where event_purchase_refund_id = %L::uuid$$,
        :'refundClearID'
    ),
    'payment job completed without its provider outcome',
    'Should reject clearing the finalization of a completed refund'
);

-- Should reject a credit note without an outcome behind a completed job
select throws_ok(
    format(
        $$insert into event_purchase_credit_note (amount_minor, currency_code, event_purchase_credit_note_id, event_purchase_refund_id, payment_job_id, payment_provider_id, provider_object_account_id, tax_amount_minor)
        values (2500, 'USD', %L::uuid, %L::uuid, %L::uuid, 'stripe', 'acct_d417', 200)$$,
        :'creditAcceptNoteID', :'creditAcceptRefundID', :'creditAcceptJobID'
    ),
    'payment job completed without its provider outcome',
    'Should reject a credit note without an outcome behind a completed job'
);

-- Should reject a fee adjustment without an outcome behind a completed job
select throws_ok(
    format(
        $$insert into event_purchase_application_fee_adjustment (amount_minor, event_purchase_application_fee_adjustment_id, event_purchase_id, kind, payment_job_id)
        values (80, %L::uuid, %L::uuid, 'tax-reconciliation', %L::uuid)$$,
        :'feeAcceptAdjustmentID', :'feeAcceptPurchaseID', :'feeAcceptJobID'
    ),
    'payment job completed without its provider outcome',
    'Should reject a fee adjustment without an outcome behind a completed job'
);

-- Should reject an unfinalized refund behind a completed job
select throws_ok(
    format(
        $$insert into event_purchase_refund (amount_minor, currency_code, event_purchase_id, event_purchase_refund_id, kind, payment_job_id, payment_provider_id, status, terminal_failure)
        values (2500, 'USD', %L::uuid, %L::uuid, 'event-cancellation', %L::uuid, 'stripe', 'provider-pending', false)$$,
        :'refundAcceptPurchaseID', :'refundAcceptID', :'refundAcceptJobID'
    ),
    'payment job completed without its provider outcome',
    'Should reject an unfinalized refund behind a completed job'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
