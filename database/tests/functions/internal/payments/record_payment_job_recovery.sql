-- Tests recording generic payment job recovery evidence.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'd40f0000-0000-0000-0000-000000000001'
\set claimedAdjustmentID 'd40f0000-0000-0000-0000-000000000002'
\set claimedClaimID 'd40f0000-0000-0000-0000-000000000003'
\set claimedJobID 'd40f0000-0000-0000-0000-000000000004'
\set claimedPurchaseID 'd40f0000-0000-0000-0000-000000000005'
\set communityID 'd40f0000-0000-0000-0000-000000000006'
\set completedAdjustmentID 'd40f0000-0000-0000-0000-000000000007'
\set completedJobID 'd40f0000-0000-0000-0000-000000000008'
\set completedPurchaseID 'd40f0000-0000-0000-0000-000000000009'
\set eventCategoryID 'd40f0000-0000-0000-0000-000000000010'
\set eventID 'd40f0000-0000-0000-0000-000000000011'
\set groupCategoryID 'd40f0000-0000-0000-0000-000000000012'
\set groupID 'd40f0000-0000-0000-0000-000000000013'
\set missingJobID 'd40f0000-0000-0000-0000-000000000014'
\set recoverableAdjustmentID 'd40f0000-0000-0000-0000-000000000015'
\set recoverableJobID 'd40f0000-0000-0000-0000-000000000016'
\set recoverablePurchaseID 'd40f0000-0000-0000-0000-000000000017'
\set ticketTypeID 'd40f0000-0000-0000-0000-000000000018'
\set userID 'd40f0000-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'actorID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with recovery-recording jobs
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by the purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Purchases owning recoverable, claimed, and completed jobs
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_object_account_id,
    provider_payment_reference, provider_total_minor,
    provisional_platform_fee_amount_minor, seller_snapshot, status,
    subtotal_excluding_tax_minor, tax_amount_minor, tax_behavior,
    tax_calculation_mode, tax_classification, ticket_title, user_id,
    venue_snapshot
) values
    (2500, 'direct-charge', 'acct_d40f', 'USD', :'eventID', :'claimedPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_claimed_d40f0000', 'ch_claimed_d40f0000', 'cs_claimed_d40f0000', 'acct_d40f', 'pi_claimed_d40f0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d40f', 'USD', :'eventID', :'completedPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_completed_d40f0000', 'ch_completed_d40f0000', 'cs_completed_d40f0000', 'acct_d40f', 'pi_completed_d40f0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d40f', 'USD', :'eventID', :'recoverablePurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_recoverable_d40f0000', 'ch_recoverable_d40f0000', 'cs_recoverable_d40f0000', 'acct_d40f', 'pi_recoverable_d40f0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb);

-- Claimed payment job that cannot be operator-recovered
insert into payment_job (
    attempt_count, claim_id, claimed_at, event_purchase_id, failure_message,
    idempotency_key, kind, payment_job_id, payment_provider_id, status
) values (
    10, :'claimedClaimID', current_timestamp, :'claimedPurchaseID',
    'automatic attempts exhausted', 'record-payment-job-recovery-claimed-d40f0000',
    'event-purchase-application-fee-adjustment', :'claimedJobID', 'stripe',
    'processing'
);

-- Completed payment job that cannot be recovered again
insert into payment_job (
    attempt_count, completed_at, event_purchase_id, idempotency_key, kind,
    payment_job_id, payment_provider_id, status
) values (
    10, current_timestamp, :'completedPurchaseID',
    'record-payment-job-recovery-completed-d40f0000',
    'event-purchase-application-fee-adjustment', :'completedJobID', 'stripe',
    'completed'
);

-- Failed unclaimed payment job ready for recovery completion
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    payment_job_id, payment_provider_id, status
) values (
    10, :'recoverablePurchaseID', 'automatic attempts exhausted',
    'record-payment-job-recovery-recoverable-d40f0000',
    'event-purchase-application-fee-adjustment', :'recoverableJobID',
    'stripe', 'failed'
);

-- Claimed adjustment with already-recorded provider outcome
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id,
    provider_application_fee_refund_id
) values (
    80, :'claimedAdjustmentID', :'claimedPurchaseID', 'purchase-refund',
    :'claimedJobID', 'fr_claimed_d40f0000'
);

-- Completed adjustment with already-recorded provider outcome
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id,
    provider_application_fee_refund_id
) values (
    80, :'completedAdjustmentID', :'completedPurchaseID', 'purchase-refund',
    :'completedJobID', 'fr_completed_d40f0000'
);

-- Recoverable adjustment with already-recorded provider outcome
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id,
    provider_application_fee_refund_id
) values (
    80, :'recoverableAdjustmentID', :'recoverablePurchaseID', 'purchase-refund',
    :'recoverableJobID', 'fr_recoverable_d40f0000'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should record recovery evidence on an unclaimed payment job
select lives_ok(
    format(
        $$select record_payment_job_recovery(%L::uuid, %L::uuid, '  case-d40f0000  ', '  Verified in provider dashboard  ')$$,
        :'recoverableJobID', :'actorID'
    ),
    'Should record recovery evidence on an unclaimed payment job'
);
select results_eq(
    format($$
        select
            claim_id,
            claimed_at,
            completed_at is not null,
            failure_message,
            recovery_completed_at is not null,
            recovery_completed_by_user_id,
            recovery_note,
            recovery_reference,
            status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'recoverableJobID'),
    format($$ values (
        null::uuid,
        null::timestamptz,
        true,
        null::text,
        true,
        %L::uuid,
        'Verified in provider dashboard'::text,
        'case-d40f0000'::text,
        'completed'::text
    ) $$, :'actorID'),
    'Should persist recovery evidence on an unclaimed payment job'
);

-- Should reject a claimed payment job
select throws_ok(
    format(
        $$select record_payment_job_recovery(%L::uuid, %L::uuid, 'case', 'note')$$,
        :'claimedJobID', :'actorID'
    ),
    'payment job is not recoverable',
    'Should reject a claimed payment job'
);

-- Should reject an already completed payment job
select throws_ok(
    format(
        $$select record_payment_job_recovery(%L::uuid, %L::uuid, 'case', 'note')$$,
        :'completedJobID', :'actorID'
    ),
    'payment job is not recoverable',
    'Should reject an already completed payment job'
);

-- Should reject a missing payment job
select throws_ok(
    format(
        $$select record_payment_job_recovery(%L::uuid, %L::uuid, 'case', 'note')$$,
        :'missingJobID', :'actorID'
    ),
    'payment job is not recoverable',
    'Should reject a missing payment job'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
