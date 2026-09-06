-- Tests enforcing payment job completion outcomes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set applicationMissingAdjustmentID 'd4160000-0000-0000-0000-000000000001'
\set applicationMissingJobID 'd4160000-0000-0000-0000-000000000002'
\set applicationMissingPurchaseID 'd4160000-0000-0000-0000-000000000003'
\set applicationReadyAdjustmentID 'd4160000-0000-0000-0000-000000000004'
\set applicationReadyJobID 'd4160000-0000-0000-0000-000000000005'
\set applicationReadyPurchaseID 'd4160000-0000-0000-0000-000000000006'
\set communityID 'd4160000-0000-0000-0000-000000000007'
\set creditMissingCreditNoteID 'd4160000-0000-0000-0000-000000000008'
\set creditMissingJobID 'd4160000-0000-0000-0000-000000000009'
\set creditMissingPurchaseID 'd4160000-0000-0000-0000-000000000010'
\set creditMissingRefundID 'd4160000-0000-0000-0000-000000000011'
\set creditMissingRefundJobID 'd4160000-0000-0000-0000-000000000012'
\set creditReadyCreditNoteID 'd4160000-0000-0000-0000-000000000013'
\set creditReadyJobID 'd4160000-0000-0000-0000-000000000014'
\set creditReadyPurchaseID 'd4160000-0000-0000-0000-000000000015'
\set creditReadyRefundID 'd4160000-0000-0000-0000-000000000016'
\set creditReadyRefundJobID 'd4160000-0000-0000-0000-000000000017'
\set eventCategoryID 'd4160000-0000-0000-0000-000000000018'
\set eventID 'd4160000-0000-0000-0000-000000000019'
\set groupCategoryID 'd4160000-0000-0000-0000-000000000020'
\set groupID 'd4160000-0000-0000-0000-000000000021'
\set insertedJobID 'd4160000-0000-0000-0000-000000000030'
\set refundMissingID 'd4160000-0000-0000-0000-000000000022'
\set refundMissingJobID 'd4160000-0000-0000-0000-000000000023'
\set refundMissingPurchaseID 'd4160000-0000-0000-0000-000000000024'
\set refundReadyID 'd4160000-0000-0000-0000-000000000025'
\set refundReadyJobID 'd4160000-0000-0000-0000-000000000026'
\set refundReadyPurchaseID 'd4160000-0000-0000-0000-000000000027'
\set ticketTypeID 'd4160000-0000-0000-0000-000000000028'
\set userID 'd4160000-0000-0000-0000-000000000029'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with completion outcome checks
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by all completion outcome purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 20,
    'title', 'General admission'
));

-- Purchases owning accepted and rejected completion outcomes
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
) values
    (2500, 'direct-charge', current_timestamp, 'acct_d416', 'USD', :'eventID', :'applicationMissingPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_application_missing_d4160000', 'ch_application_missing_d4160000', 'cs_application_missing_d4160000', 'in_application_missing_d4160000', 'acct_d416', 'pi_application_missing_d4160000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d416', 'USD', :'eventID', :'applicationReadyPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_application_ready_d4160000', 'ch_application_ready_d4160000', 'cs_application_ready_d4160000', 'in_application_ready_d4160000', 'acct_d416', 'pi_application_ready_d4160000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d416', 'USD', :'eventID', :'creditMissingPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_credit_missing_d4160000', 'ch_credit_missing_d4160000', 'cs_credit_missing_d4160000', 'in_credit_missing_d4160000', 'acct_d416', 'pi_credit_missing_d4160000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d416', 'USD', :'eventID', :'creditReadyPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_credit_ready_d4160000', 'ch_credit_ready_d4160000', 'cs_credit_ready_d4160000', 'in_credit_ready_d4160000', 'acct_d416', 'pi_credit_ready_d4160000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d416', 'USD', :'eventID', :'refundMissingPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_refund_missing_d4160000', 'ch_refund_missing_d4160000', 'cs_refund_missing_d4160000', 'in_refund_missing_d4160000', 'acct_d416', 'pi_refund_missing_d4160000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d416', 'USD', :'eventID', :'refundReadyPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_refund_ready_d4160000', 'ch_refund_ready_d4160000', 'cs_refund_ready_d4160000', 'in_refund_ready_d4160000', 'acct_d416', 'pi_refund_ready_d4160000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb);

-- Application-fee job whose domain outcome is missing
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'applicationMissingPurchaseID',
    'check-payment-job-completion-application-missing-d4160000',
    'event-purchase-application-fee-adjustment', :'applicationMissingJobID',
    'stripe'
);

-- Application-fee job whose domain outcome exists
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'applicationReadyPurchaseID',
    'check-payment-job-completion-application-ready-d4160000',
    'event-purchase-application-fee-adjustment', :'applicationReadyJobID',
    'stripe'
);

-- Credit-note job whose domain outcome is missing
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'creditMissingPurchaseID',
    'check-payment-job-completion-credit-missing-d4160000',
    'event-purchase-credit-note', :'creditMissingJobID', 'stripe'
);

-- Refund job behind the credit note without a provider outcome
insert into payment_job (
    completed_at, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id, status
) values (
    current_timestamp, :'creditMissingPurchaseID',
    'check-payment-job-completion-credit-missing-refund-d4160000',
    'event-purchase-refund', :'creditMissingRefundJobID', 'stripe',
    'completed'
);

-- Credit-note job whose domain outcome exists
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'creditReadyPurchaseID',
    'check-payment-job-completion-credit-ready-d4160000',
    'event-purchase-credit-note', :'creditReadyJobID', 'stripe'
);

-- Refund job behind the credit note with a provider outcome
insert into payment_job (
    completed_at, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id, status
) values (
    current_timestamp, :'creditReadyPurchaseID',
    'check-payment-job-completion-credit-ready-refund-d4160000',
    'event-purchase-refund', :'creditReadyRefundJobID', 'stripe',
    'completed'
);

-- Refund job whose local finalization is missing
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'refundMissingPurchaseID',
    'check-payment-job-completion-refund-missing-d4160000',
    'event-purchase-refund', :'refundMissingJobID', 'stripe'
);

-- Refund job whose local finalization exists
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'refundReadyPurchaseID',
    'check-payment-job-completion-refund-ready-d4160000',
    'event-purchase-refund', :'refundReadyJobID', 'stripe'
);

-- Application-fee adjustment without a provider outcome
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id
) values (
    80, :'applicationMissingAdjustmentID', :'applicationMissingPurchaseID',
    'purchase-refund', :'applicationMissingJobID'
);

-- Application-fee adjustment with a provider outcome
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id,
    provider_application_fee_refund_id
) values (
    80, :'applicationReadyAdjustmentID', :'applicationReadyPurchaseID',
    'purchase-refund', :'applicationReadyJobID', 'fr_ready_d4160000'
);

-- Finalized refund behind the credit note whose outcome is missing
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, provider_refunded_at, status, terminal_failure
) values (
    2500, 'USD', :'creditMissingPurchaseID', :'creditMissingRefundID',
    current_timestamp, 'event-cancellation', :'creditMissingRefundJobID',
    'stripe', 're_credit_missing_d4160000', current_timestamp, 'finalized',
    false
);

-- Refund with finalization behind the credit note whose outcome exists
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, provider_refunded_at, status, terminal_failure
) values (
    2500, 'USD', :'creditReadyPurchaseID', :'creditReadyRefundID',
    current_timestamp, 'event-cancellation', :'creditReadyRefundJobID',
    'stripe', 're_credit_ready_d4160000', current_timestamp, 'finalized',
    false
);

-- Refund whose local finalization is missing
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, status, terminal_failure
) values (
    2500, 'USD', :'refundMissingPurchaseID', :'refundMissingID',
    'event-cancellation', :'refundMissingJobID', 'stripe', 'provider-pending',
    false
);

-- Refund whose local finalization exists
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, provider_refunded_at, status, terminal_failure
) values (
    2500, 'USD', :'refundReadyPurchaseID', :'refundReadyID',
    current_timestamp, 'event-cancellation', :'refundReadyJobID', 'stripe',
    're_refund_ready_d4160000', current_timestamp, 'finalized', false
);

-- Credit note without a provider outcome
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'creditMissingCreditNoteID', :'creditMissingRefundID',
    :'creditMissingJobID', 'stripe', 'acct_d416', 200
);

-- Credit note with a provider outcome
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_credit_note_id, provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'creditReadyCreditNoteID', :'creditReadyRefundID',
    :'creditReadyJobID', 'stripe', 'cn_ready_d4160000', 'acct_d416', 200
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept application-fee completion with an outcome
select lives_ok(
    format(
        $$update payment_job set completed_at = current_timestamp, status = 'completed' where payment_job_id = %L::uuid$$,
        :'applicationReadyJobID'
    ),
    'Should accept application-fee completion with an outcome'
);

-- Should accept credit-note completion with an outcome
select lives_ok(
    format(
        $$update payment_job set completed_at = current_timestamp, status = 'completed' where payment_job_id = %L::uuid$$,
        :'creditReadyJobID'
    ),
    'Should accept credit-note completion with an outcome'
);

-- Should accept refund completion with an outcome
select lives_ok(
    format(
        $$update payment_job set completed_at = current_timestamp, status = 'completed' where payment_job_id = %L::uuid$$,
        :'refundReadyJobID'
    ),
    'Should accept refund completion with an outcome'
);

-- Should reject application-fee completion without an outcome
select throws_ok(
    format(
        $$update payment_job set completed_at = current_timestamp, status = 'completed' where payment_job_id = %L::uuid$$,
        :'applicationMissingJobID'
    ),
    'payment job completed without its provider outcome',
    'Should reject application-fee completion without an outcome'
);

-- Should reject credit-note completion without an outcome
select throws_ok(
    format(
        $$update payment_job set completed_at = current_timestamp, status = 'completed' where payment_job_id = %L::uuid$$,
        :'creditMissingJobID'
    ),
    'payment job completed without its provider outcome',
    'Should reject credit-note completion without an outcome'
);

-- Should reject refund completion without an outcome
select throws_ok(
    format(
        $$update payment_job set completed_at = current_timestamp, status = 'completed' where payment_job_id = %L::uuid$$,
        :'refundMissingJobID'
    ),
    'payment job completed without its provider outcome',
    'Should reject refund completion without an outcome'
);

-- Check the deferred insert trigger at the end of each statement from here on
set constraints payment_job_completion_outcome_insert_check immediate;

-- Should reject inserting a completed job before its domain row exists
select throws_ok(
    format(
        $$insert into payment_job (completed_at, event_purchase_id, idempotency_key, kind, payment_job_id, payment_provider_id, status)
        values (current_timestamp, %L::uuid, 'check-payment-job-completion-inserted-d4160000', 'event-purchase-refund', %L::uuid, 'stripe', 'completed')$$,
        :'refundMissingPurchaseID',
        :'insertedJobID'
    ),
    'payment job completed without its provider outcome',
    'Should reject inserting a completed job before its domain row exists'
);

-- Should accept inserting a pending job without a domain row
select lives_ok(
    format(
        $$insert into payment_job (event_purchase_id, idempotency_key, kind, payment_job_id, payment_provider_id)
        values (%L::uuid, 'check-payment-job-completion-inserted-d4160000', 'event-purchase-refund', %L::uuid, 'stripe')$$,
        :'refundMissingPurchaseID',
        :'insertedJobID'
    ),
    'Should accept inserting a pending job without a domain row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
