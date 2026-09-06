-- Tests operator completion of exhausted payment jobs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'd4120000-0000-0000-0000-000000000001'
\set buyerID 'd4120000-0000-0000-0000-000000000002'
\set communityID 'd4120000-0000-0000-0000-000000000003'
\set creditJobID 'd4120000-0000-0000-0000-000000000004'
\set creditNoteID 'd4120000-0000-0000-0000-000000000005'
\set creditPurchaseID 'd4120000-0000-0000-0000-000000000006'
\set creditRefundID 'd4120000-0000-0000-0000-000000000007'
\set creditRefundJobID 'd4120000-0000-0000-0000-000000000008'
\set eventCategoryID 'd4120000-0000-0000-0000-000000000009'
\set eventID 'd4120000-0000-0000-0000-000000000010'
\set feeAdjustmentID 'd4120000-0000-0000-0000-000000000011'
\set feeJobID 'd4120000-0000-0000-0000-000000000012'
\set feePurchaseID 'd4120000-0000-0000-0000-000000000013'
\set groupCategoryID 'd4120000-0000-0000-0000-000000000014'
\set groupID 'd4120000-0000-0000-0000-000000000015'
\set lowAdjustmentID 'd4120000-0000-0000-0000-000000000016'
\set lowJobID 'd4120000-0000-0000-0000-000000000017'
\set lowPurchaseID 'd4120000-0000-0000-0000-000000000018'
\set missingGroupID 'd4120000-0000-0000-0000-000000000019'
\set missingJobID 'd4120000-0000-0000-0000-000000000020'
\set refundJobID 'd4120000-0000-0000-0000-000000000021'
\set refundPurchaseID 'd4120000-0000-0000-0000-000000000022'
\set ticketTypeID 'd4120000-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'actorID');
select fx_user(:'buyerID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with recoverable payment jobs
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by recovery purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Purchases owning fee-adjustment, credit-note, refund-kind, and ineligible jobs
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
    (2500, 'direct-charge', current_timestamp, 'acct_d412', 'USD', :'eventID', :'creditPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_credit_recovery_d4120000', 'ch_credit_recovery_d4120000', 'cs_credit_recovery_d4120000', 'in_credit_recovery_d4120000', 'acct_d412', 'pi_credit_recovery_d4120000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'buyerID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d412', 'USD', :'eventID', :'feePurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_fee_recovery_d4120000', 'ch_fee_recovery_d4120000', 'cs_fee_recovery_d4120000', 'in_fee_recovery_d4120000', 'acct_d412', 'pi_fee_recovery_d4120000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'buyerID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d412', 'USD', :'eventID', :'lowPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_low_recovery_d4120000', 'ch_low_recovery_d4120000', 'cs_low_recovery_d4120000', 'in_low_recovery_d4120000', 'acct_d412', 'pi_low_recovery_d4120000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'buyerID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d412', 'USD', :'eventID', :'refundPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_refund_recovery_d4120000', 'ch_refund_recovery_d4120000', 'cs_refund_recovery_d4120000', 'in_refund_recovery_d4120000', 'acct_d412', 'pi_refund_recovery_d4120000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'buyerID', '{}'::jsonb);

-- Exhausted credit-note payment job ready for recovery
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    payment_job_id, payment_provider_id, status
) values (
    10, :'creditPurchaseID', 'automatic attempts exhausted',
    'complete-payment-job-recovery-credit-d4120000',
    'event-purchase-credit-note', :'creditJobID', 'stripe', 'failed'
);

-- Completed refund payment job behind the credit note
insert into payment_job (
    completed_at, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id, status
) values (
    current_timestamp, :'creditPurchaseID',
    'complete-payment-job-recovery-credit-refund-d4120000',
    'event-purchase-refund', :'creditRefundJobID', 'stripe', 'completed'
);

-- Exhausted application-fee payment job ready for recovery
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    payment_job_id, payment_provider_id, status
) values (
    10, :'feePurchaseID', 'automatic attempts exhausted',
    'complete-payment-job-recovery-fee-d4120000',
    'event-purchase-application-fee-adjustment', :'feeJobID', 'stripe',
    'failed'
);

-- Application-fee payment job below the automatic attempt cap
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    payment_job_id, payment_provider_id, status
) values (
    9, :'lowPurchaseID', 'provider unavailable',
    'complete-payment-job-recovery-low-d4120000',
    'event-purchase-application-fee-adjustment', :'lowJobID', 'stripe',
    'failed'
);

-- Exhausted refund payment job that must use refund recovery instead
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    payment_job_id, payment_provider_id, status
) values (
    10, :'refundPurchaseID', 'automatic attempts exhausted',
    'complete-payment-job-recovery-refund-kind-d4120000',
    'event-purchase-refund', :'refundJobID', 'stripe', 'failed'
);

-- Provider-confirmed refund documented by the recoverable credit note
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, provider_refunded_at, status, terminal_failure
) values (
    2500, 'USD', :'creditPurchaseID', :'creditRefundID', current_timestamp,
    'automatic-unfulfillable-checkout', :'creditRefundJobID', 'stripe',
    're_credit_recovery_d4120000', current_timestamp, 'finalized', false
);

-- Recoverable credit note awaiting external evidence
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'creditNoteID', :'creditRefundID', :'creditJobID',
    'stripe', 'acct_d412', 200
);

-- Recoverable tax-reconciliation adjustment awaiting external evidence
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id
) values (
    20, :'feeAdjustmentID', :'feePurchaseID', 'tax-reconciliation',
    :'feeJobID'
);

-- Application-fee adjustment whose job is below the automatic attempt cap
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id
) values (
    20, :'lowAdjustmentID', :'lowPurchaseID', 'purchase-refund', :'lowJobID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should require an actor user id
select throws_ok(
    format(
        $$select complete_payment_job_recovery(null, %L::uuid, %L::uuid, 'fr_recovered_d4120000', 'case-d4120000', 'Verified Stripe activity')$$,
        :'groupID', :'feeJobID'
    ),
    'actor user id is required',
    'Should require an actor user id'
);

-- Should require a group id
select throws_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, null, %L::uuid, 'fr_recovered_d4120000', 'case-d4120000', 'Verified Stripe activity')$$,
        :'actorID', :'feeJobID'
    ),
    'group id is required',
    'Should require a group id'
);

-- Should require a provider object id
select throws_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, '   ', 'case-d4120000', 'Verified Stripe activity')$$,
        :'actorID', :'groupID', :'feeJobID'
    ),
    'OCG01',
    'provider object id is required',
    'Should require a provider object id'
);

-- Should require a recovery note
select throws_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, 'fr_recovered_d4120000', 'case-d4120000', '   ')$$,
        :'actorID', :'groupID', :'feeJobID'
    ),
    'OCG01',
    'recovery note is required',
    'Should require a recovery note'
);

-- Should require a recovery reference
select throws_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, 'fr_recovered_d4120000', '   ', 'Verified Stripe activity')$$,
        :'actorID', :'groupID', :'feeJobID'
    ),
    'OCG01',
    'recovery reference is required',
    'Should require a recovery reference'
);

-- Should reject a missing payment job
select throws_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, 'fr_recovered_d4120000', 'case-d4120000', 'Verified Stripe activity')$$,
        :'actorID', :'groupID', :'missingJobID'
    ),
    'OCG01',
    'recoverable payment job not found',
    'Should reject a missing payment job'
);

-- Should reject a payment job outside the requested group
select throws_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, 'fr_recovered_d4120000', 'case-d4120000', 'Verified Stripe activity')$$,
        :'actorID', :'missingGroupID', :'feeJobID'
    ),
    'OCG01',
    'recoverable payment job not found',
    'Should reject a payment job outside the requested group'
);

-- Should reject a refund payment job
select throws_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, 're_recovered_d4120000', 'case-d4120000', 'Verified Stripe activity')$$,
        :'actorID', :'groupID', :'refundJobID'
    ),
    'payment job kind does not support provider object recovery',
    'Should reject a refund payment job'
);

-- Should reject payment work before automatic attempts are exhausted
select throws_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, 'fr_low_d4120000', 'case-d4120000', 'Verified Stripe activity')$$,
        :'actorID', :'groupID', :'lowJobID'
    ),
    'OCG01',
    'recoverable payment job not found',
    'Should reject payment work before automatic attempts are exhausted'
);

-- Should complete an application-fee adjustment resolved outside OCG
select lives_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, 'fr_recovered_d4120000', 'case-fee-d4120000', 'Verified Stripe fee activity')$$,
        :'actorID', :'groupID', :'feeJobID'
    ),
    'Should complete an application-fee adjustment resolved outside OCG'
);
select results_eq(
    format($$
        select
            a.provider_application_fee_refund_id,
            p.financially_reconciled_at is not null,
            j.completed_at is not null,
            j.failure_message,
            j.recovery_completed_by_user_id,
            j.recovery_note,
            j.recovery_reference,
            j.status
        from payment_job j
        join event_purchase_application_fee_adjustment a using (payment_job_id)
        join event_purchase p on p.event_purchase_id = a.event_purchase_id
        where j.payment_job_id = %L::uuid
    $$, :'feeJobID'),
    format($$ values (
        'fr_recovered_d4120000'::text,
        true,
        true,
        null::text,
        %L::uuid,
        'Verified Stripe fee activity'::text,
        'case-fee-d4120000'::text,
        'completed'::text
    ) $$, :'actorID'),
    'Should persist an application-fee adjustment resolved outside OCG'
);

-- Should audit application-fee recovery evidence
select results_eq(
    format($$
        select
            action,
            actor_user_id,
            details->>'event_purchase_application_fee_adjustment_id',
            details->>'event_purchase_id',
            details->>'kind',
            details->>'payment_job_id',
            details->>'provider_application_fee_refund_id',
            details->>'recovery_note',
            details->>'recovery_reference'
        from audit_log
        where action = 'event_application_fee_adjustment_recovery_completed'
    $$),
    format($$ values (
        'event_application_fee_adjustment_recovery_completed'::text,
        %L::uuid,
        %L::text,
        %L::text,
        'tax-reconciliation'::text,
        %L::text,
        'fr_recovered_d4120000'::text,
        'Verified Stripe fee activity'::text,
        'case-fee-d4120000'::text
    ) $$, :'actorID', :'feeAdjustmentID', :'feePurchaseID', :'feeJobID'),
    'Should audit application-fee recovery evidence'
);

-- Should accept an exact payment job recovery replay
select lives_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, 'fr_recovered_d4120000', 'case-fee-d4120000', 'Verified Stripe fee activity')$$,
        :'actorID', :'groupID', :'feeJobID'
    ),
    'Should accept an exact payment job recovery replay'
);

-- Should reject conflicting recovery evidence
select throws_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, 'fr_other_d4120000', 'case-fee-d4120000', 'Verified Stripe fee activity')$$,
        :'actorID', :'groupID', :'feeJobID'
    ),
    'OCG01',
    'payment job recovery already completed with different evidence',
    'Should reject conflicting recovery evidence'
);

-- Should complete a credit note resolved outside OCG
select lives_ok(
    format(
        $$select complete_payment_job_recovery(%L::uuid, %L::uuid, %L::uuid, 'cn_recovered_d4120000', 'case-credit-d4120000', 'Verified Stripe credit activity')$$,
        :'actorID', :'groupID', :'creditJobID'
    ),
    'Should complete a credit note resolved outside OCG'
);
select results_eq(
    format($$
        select
            c.provider_credit_note_id,
            c.provider_hosted_url,
            c.provider_pdf_url,
            j.completed_at is not null,
            j.failure_message,
            j.recovery_completed_by_user_id,
            j.recovery_note,
            j.recovery_reference,
            j.status
        from payment_job j
        join event_purchase_credit_note c using (payment_job_id)
        where j.payment_job_id = %L::uuid
    $$, :'creditJobID'),
    format($$ values (
        'cn_recovered_d4120000'::text,
        null::text,
        null::text,
        true,
        null::text,
        %L::uuid,
        'Verified Stripe credit activity'::text,
        'case-credit-d4120000'::text,
        'completed'::text
    ) $$, :'actorID'),
    'Should persist a credit note resolved outside OCG'
);

-- Should audit credit-note recovery evidence
select results_eq(
    format($$
        select
            action,
            actor_user_id,
            details->>'event_purchase_credit_note_id',
            details->>'event_purchase_id',
            details->>'payment_job_id',
            details->>'provider_credit_note_id',
            details->>'recovery_note',
            details->>'recovery_reference'
        from audit_log
        where action = 'event_credit_note_recovery_completed'
    $$),
    format($$ values (
        'event_credit_note_recovery_completed'::text,
        %L::uuid,
        %L::text,
        %L::text,
        %L::text,
        'cn_recovered_d4120000'::text,
        'Verified Stripe credit activity'::text,
        'case-credit-d4120000'::text
    ) $$, :'actorID', :'creditNoteID', :'creditPurchaseID', :'creditJobID'),
    'Should audit credit-note recovery evidence'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
