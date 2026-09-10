-- Tests completing payment jobs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set claimID 'd4040000-0000-0000-0000-000000000001'
\set communityID 'd4040000-0000-0000-0000-000000000002'
\set eventCategoryID 'd4040000-0000-0000-0000-000000000003'
\set eventID 'd4040000-0000-0000-0000-000000000004'
\set groupCategoryID 'd4040000-0000-0000-0000-000000000005'
\set groupID 'd4040000-0000-0000-0000-000000000006'
\set idempotentJobID 'd4040000-0000-0000-0000-000000000007'
\set idempotentPurchaseID 'd4040000-0000-0000-0000-000000000008'
\set idempotentRefundID 'd4040000-0000-0000-0000-000000000009'
\set matchingAdjustmentID 'd4040000-0000-0000-0000-000000000010'
\set matchingJobID 'd4040000-0000-0000-0000-000000000011'
\set matchingPurchaseID 'd4040000-0000-0000-0000-000000000012'
\set missingOutcomeAdjustmentID 'd4040000-0000-0000-0000-000000000013'
\set missingOutcomeJobID 'd4040000-0000-0000-0000-000000000014'
\set missingOutcomePurchaseID 'd4040000-0000-0000-0000-000000000015'
\set staleAdjustmentID 'd4040000-0000-0000-0000-000000000016'
\set staleClaimID 'd4040000-0000-0000-0000-000000000017'
\set staleJobID 'd4040000-0000-0000-0000-000000000018'
\set stalePurchaseID 'd4040000-0000-0000-0000-000000000019'
\set ticketTypeID 'd4040000-0000-0000-0000-000000000020'
\set unclaimedAdjustmentID 'd4040000-0000-0000-0000-000000000021'
\set unclaimedJobID 'd4040000-0000-0000-0000-000000000022'
\set unclaimedPurchaseID 'd4040000-0000-0000-0000-000000000023'
\set userID 'd4040000-0000-0000-0000-000000000024'
\set wrongClaimID 'd4040000-0000-0000-0000-000000000025'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with all completion scenarios
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by all purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Purchases owning all jobs under completion
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
    (2500, 'direct-charge', 'acct_d404', 'USD', :'eventID', :'idempotentPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_idempotent_d4040000', 'ch_idempotent_d4040000', 'cs_idempotent_d4040000', 'acct_d404', 'pi_idempotent_d4040000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d404', 'USD', :'eventID', :'matchingPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_matching_d4040000', 'ch_matching_d4040000', 'cs_matching_d4040000', 'acct_d404', 'pi_matching_d4040000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d404', 'USD', :'eventID', :'missingOutcomePurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_missing_d4040000', 'ch_missing_d4040000', 'cs_missing_d4040000', 'acct_d404', 'pi_missing_d4040000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d404', 'USD', :'eventID', :'stalePurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_stale_d4040000', 'ch_stale_d4040000', 'cs_stale_d4040000', 'acct_d404', 'pi_stale_d4040000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d404', 'USD', :'eventID', :'unclaimedPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_unclaimed_d4040000', 'ch_unclaimed_d4040000', 'cs_unclaimed_d4040000', 'acct_d404', 'pi_unclaimed_d4040000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb);

-- Completed payment job used by idempotent replay
insert into payment_job (
    completed_at, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id, status
) values (
    '2024-01-01 00:00:00+00', :'idempotentPurchaseID',
    'complete-payment-job-idempotent-d4040000', 'event-purchase-refund',
    :'idempotentJobID', 'stripe', 'completed'
);

-- Processing payment job held by the expected claim
insert into payment_job (
    claim_id, claimed_at, event_purchase_id, idempotency_key, kind,
    payment_job_id, payment_provider_id, status
) values (
    :'claimID', current_timestamp, :'matchingPurchaseID',
    'complete-payment-job-matching-d4040000',
    'event-purchase-application-fee-adjustment', :'matchingJobID', 'stripe',
    'processing'
);

-- Pending payment job whose domain outcome is missing
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'missingOutcomePurchaseID', 'complete-payment-job-missing-outcome-d4040000',
    'event-purchase-application-fee-adjustment', :'missingOutcomeJobID',
    'stripe'
);

-- Processing payment job held by another worker
insert into payment_job (
    claim_id, claimed_at, event_purchase_id, idempotency_key, kind,
    payment_job_id, payment_provider_id, status
) values (
    :'staleClaimID', current_timestamp, :'stalePurchaseID',
    'complete-payment-job-stale-d4040000',
    'event-purchase-application-fee-adjustment', :'staleJobID', 'stripe',
    'processing'
);

-- Unclaimed payment job ready to complete
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'unclaimedPurchaseID', 'complete-payment-job-unclaimed-d4040000',
    'event-purchase-application-fee-adjustment', :'unclaimedJobID', 'stripe'
);

-- Finalized refund domain outcome backing the completed job
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, status, terminal_failure
) values (
    2500, 'USD', :'idempotentPurchaseID', :'idempotentRefundID',
    '2024-01-01 00:00:00+00', 'event-cancellation', :'idempotentJobID',
    'stripe', 're_idempotent_d4040000', 'finalized', false
);

-- Adjustment outcome backing the expected-claim completion
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id,
    provider_application_fee_refund_id
) values (
    80, :'matchingAdjustmentID', :'matchingPurchaseID', 'purchase-refund',
    :'matchingJobID', 'fr_matching_d4040000'
);

-- Adjustment without an outcome used to prove trigger enforcement
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id
) values (
    80, :'missingOutcomeAdjustmentID', :'missingOutcomePurchaseID',
    'purchase-refund', :'missingOutcomeJobID'
);

-- Adjustment outcome backing the stale-claim rejection
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id,
    provider_application_fee_refund_id
) values (
    80, :'staleAdjustmentID', :'stalePurchaseID', 'purchase-refund',
    :'staleJobID', 'fr_stale_d4040000'
);

-- Adjustment outcome backing the unclaimed completion
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id,
    provider_application_fee_refund_id
) values (
    80, :'unclaimedAdjustmentID', :'unclaimedPurchaseID', 'purchase-refund',
    :'unclaimedJobID', 'fr_unclaimed_d4040000'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should complete an unclaimed payment job with a null claim
select lives_ok(
    format(
        $$select complete_payment_job(%L::uuid, null::uuid)$$,
        :'unclaimedJobID'
    ),
    'Should complete an unclaimed payment job with a null claim'
);
select results_eq(
    format($$
        select
            claim_id,
            claimed_at,
            completed_at is not null,
            status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'unclaimedJobID'),
    $$ values (null::uuid, null::timestamptz, true, 'completed'::text) $$,
    'Should persist unclaimed payment job completion'
);

-- Should complete a payment job held by the matching claim
select lives_ok(
    format(
        $$select complete_payment_job(%L::uuid, %L::uuid)$$,
        :'matchingJobID', :'claimID'
    ),
    'Should complete a payment job held by the matching claim'
);
select results_eq(
    format($$
        select
            claim_id,
            claimed_at,
            completed_at is not null,
            status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'matchingJobID'),
    $$ values (null::uuid, null::timestamptz, true, 'completed'::text) $$,
    'Should persist matching-claim payment job completion'
);

-- Should accept an already completed payment job as idempotent
select lives_ok(
    format(
        $$select complete_payment_job(%L::uuid, %L::uuid)$$,
        :'idempotentJobID', :'wrongClaimID'
    ),
    'Should accept an already completed payment job as idempotent'
);

-- Should reject completion from a stale claim
select throws_ok(
    format(
        $$select complete_payment_job(%L::uuid, %L::uuid)$$,
        :'staleJobID', :'wrongClaimID'
    ),
    'payment job claim is stale',
    'Should reject completion from a stale claim'
);

-- Should reject completion before the domain outcome is recorded
select throws_ok(
    format(
        $$select complete_payment_job(%L::uuid, null::uuid)$$,
        :'missingOutcomeJobID'
    ),
    'payment job completed without its provider outcome',
    'Should reject completion before the domain outcome is recorded'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
