-- Tests releasing failed application-fee adjustment claims.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adjustmentID 'd7330000-0000-0000-0000-000000000001'
\set claimID 'd7330000-0000-0000-0000-000000000002'
\set communityID 'd7330000-0000-0000-0000-000000000003'
\set eventCategoryID 'd7330000-0000-0000-0000-000000000004'
\set eventID 'd7330000-0000-0000-0000-000000000005'
\set finalAdjustmentID 'd7330000-0000-0000-0000-000000000012'
\set finalClaimID 'd7330000-0000-0000-0000-000000000013'
\set groupCategoryID 'd7330000-0000-0000-0000-000000000006'
\set groupID 'd7330000-0000-0000-0000-000000000007'
\set purchaseID 'd7330000-0000-0000-0000-000000000008'
\set ticketTypeID 'd7330000-0000-0000-0000-000000000009'
\set userID 'd7330000-0000-0000-0000-000000000010'
\set wrongClaimID 'd7330000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with the direct-charge purchase
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('payment_currency_code', 'USD'));

-- Ticket type snapshotted by the purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Direct-charge purchase owning both adjustment kinds
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
) values (
    2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'purchaseID',
    :'ticketTypeID', 80, 'stripe', 'fee_adjust', 'ch_adjust_record_event_purchase_application_fee_adjustment_failure', 'cs_adjust_record_event_purchase_application_fee_adjustment_failure',
    'acct_fee', 'pi_adjust_record_event_purchase_application_fee_adjustment_failure', 2500, 100,
    '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'userID', '{}'::jsonb
);

-- Retryable and final-attempt application-fee claims
insert into event_purchase_application_fee_adjustment (
    amount_minor, attempt_count, claim_id, claimed_at,
    event_purchase_application_fee_adjustment_id, event_purchase_id,
    idempotency_key, kind, status
) values
    (
        20, 1, :'claimID', current_timestamp, :'adjustmentID', :'purchaseID',
        'fail-fee-adjustment', 'tax-reconciliation', 'processing'
    ),
    (
        80, 10, :'finalClaimID', current_timestamp, :'finalAdjustmentID',
        :'purchaseID', 'fail-final-fee-adjustment', 'purchase-refund',
        'processing'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a stale application-fee failure claim
select throws_ok(
    format(
        'select record_event_purchase_application_fee_adjustment_failure(%L, %L, %L)',
        :'adjustmentID', :'wrongClaimID', 'wrong claim'
    ),
    'application-fee adjustment claim is stale',
    'Should reject a stale application-fee failure claim'
);

-- Should release a failed application-fee claim for retry
select lives_ok(
    format(
        'select record_event_purchase_application_fee_adjustment_failure(%L, %L, %L)',
        :'adjustmentID', :'claimID', 'temporary provider failure'
    ),
    'Should release a failed application-fee claim for retry'
);

-- Should persist the retryable application-fee failure
select results_eq(
    format($$
        select attempt_count, claim_id, failure_message, status
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'adjustmentID'),
    $$ values (
        1, null::uuid, 'temporary provider failure'::text, 'failed'::text
    ) $$,
    'Should persist the retryable application-fee failure'
);

-- Should release the final automatic application-fee claim for recovery
select lives_ok(
    format(
        'select record_event_purchase_application_fee_adjustment_failure(%L, %L, %L)',
        :'finalAdjustmentID', :'finalClaimID', 'final provider failure'
    ),
    'Should release the final automatic application-fee claim for recovery'
);

-- Should preserve the exhausted attempt count for operator recovery
select results_eq(
    format($$
        select attempt_count, claim_id, failure_message, status
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'finalAdjustmentID'),
    $$ values (
        10, null::uuid, 'final provider failure'::text, 'failed'::text
    ) $$,
    'Should preserve the exhausted attempt count for operator recovery'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
