-- Tests claiming durable application-fee adjustments.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adjustmentID '79030000-0000-0000-0000-000000000001'
\set blockedAdjustmentID '79030000-0000-0000-0000-000000000020'
\set blockedPurchaseID '79030000-0000-0000-0000-000000000021'
\set blockedUserID '79030000-0000-0000-0000-000000000022'
\set communityID '79030000-0000-0000-0000-000000000002'
\set eventCategoryID '79030000-0000-0000-0000-000000000003'
\set eventID '79030000-0000-0000-0000-000000000004'
\set finalAdjustmentID '79030000-0000-0000-0000-000000000010'
\set finalPurchaseID '79030000-0000-0000-0000-000000000011'
\set finalUserID '79030000-0000-0000-0000-000000000017'
\set groupCategoryID '79030000-0000-0000-0000-000000000005'
\set groupID '79030000-0000-0000-0000-000000000006'
\set purchaseID '79030000-0000-0000-0000-000000000007'
\set retryAdjustmentID '79030000-0000-0000-0000-000000000012'
\set retryPurchaseID '79030000-0000-0000-0000-000000000013'
\set retryUserID '79030000-0000-0000-0000-000000000018'
\set staleAdjustmentID '79030000-0000-0000-0000-000000000014'
\set staleClaimID '79030000-0000-0000-0000-000000000015'
\set stalePurchaseID '79030000-0000-0000-0000-000000000016'
\set staleUserID '79030000-0000-0000-0000-000000000019'
\set ticketTypeID '79030000-0000-0000-0000-000000000008'
\set userID '79030000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'blockedUserID');
select fx_user(:'finalUserID');
select fx_user(:'retryUserID');
select fx_user(:'staleUserID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with the direct-charge purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('payment_currency_code', 'USD'));

-- Ticket type snapshotted by each purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Purchases providing immutable context for each claim state
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
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'blockedPurchaseID',
        :'ticketTypeID', 80, 'stripe', null, 'ch_blocked', 'cs_blocked',
        'acct_fee', 'pi_blocked', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'blockedUserID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'purchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_adjust', 'ch_adjust', 'cs_adjust',
        'acct_fee', 'pi_adjust', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'retryPurchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_retry', 'ch_retry', 'cs_retry',
        'acct_fee', 'pi_retry', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'retryUserID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'stalePurchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_stale', 'ch_stale', 'cs_stale',
        'acct_fee', 'pi_stale', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'staleUserID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'finalPurchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_final', 'ch_final', 'cs_final',
        'acct_fee', 'pi_final', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'finalUserID', '{}'::jsonb
    );

-- Pending, retryable, stale, and exhausted claim fixtures
insert into event_purchase_application_fee_adjustment (
    amount_minor, attempt_count, claim_id, claimed_at, created_at,
    event_purchase_application_fee_adjustment_id, event_purchase_id,
    failure_message, idempotency_key, kind, next_attempt_at, status
) values
    (
        20, 0, null, null, '2023-12-31 00:00:00+00', :'blockedAdjustmentID',
        :'blockedPurchaseID', null, 'claim-blocked-fee-adjustment',
        'tax-reconciliation', '2023-12-31 00:00:00+00', 'pending'
    ),
    (
        20, 0, null, null, '2024-01-01 00:00:00+00', :'adjustmentID',
        :'purchaseID', null, 'claim-fee-adjustment', 'tax-reconciliation',
        '2024-01-01 00:00:00+00', 'pending'
    ),
    (
        80, 1, null, null, '2024-01-02 00:00:00+00', :'retryAdjustmentID',
        :'retryPurchaseID', 'provider unavailable', 'claim-retry-fee-adjustment',
        'purchase-refund', '2024-01-02 00:00:00+00', 'failed'
    ),
    (
        20, 1, :'staleClaimID', current_timestamp - interval '16 minutes',
        '2024-01-03 00:00:00+00', :'staleAdjustmentID', :'stalePurchaseID',
        null, 'claim-stale-fee-adjustment', 'tax-reconciliation',
        '2024-01-03 00:00:00+00', 'processing'
    ),
    (
        80, 10, gen_random_uuid(), current_timestamp - interval '16 minutes',
        '2024-01-04 00:00:00+00', :'finalAdjustmentID', :'finalPurchaseID',
        'provider timed out', 'claim-final-fee-adjustment', 'purchase-refund',
        '2024-01-04 00:00:00+00', 'processing'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should skip work waiting for its fee identifier and claim complete context
create temporary table first_claim as
select claim_event_purchase_application_fee_adjustment('stripe') as item;
select results_eq(
    $$
        select
            item->>'amount_minor',
            (
                select attempt_count::text
                from event_purchase_application_fee_adjustment
                where event_purchase_application_fee_adjustment_id =
                    (item->>'event_purchase_application_fee_adjustment_id')::uuid
            ),
            (item->>'claim_id') is not null,
            item->>'connected_seller_id',
            item->>'currency_code',
            item->>'event_purchase_application_fee_adjustment_id',
            item->>'event_purchase_id',
            item->>'idempotency_key',
            item->>'kind',
            item->>'provider_application_fee_id'
        from first_claim
    $$,
    format(
        $$ values (
            '20'::text, '1'::text, true, 'acct_fee'::text, 'USD'::text,
            %L::text, %L::text, 'claim-fee-adjustment'::text,
            'tax-reconciliation'::text, 'fee_adjust'::text
        ) $$,
        :'adjustmentID', :'purchaseID'
    ),
    'Should skip work waiting for its fee identifier and claim complete context'
);

-- Should claim failed application-fee work as the next retry attempt
create temporary table retry_claim as
select claim_event_purchase_application_fee_adjustment('stripe') as item;
select results_eq(
    $$
        select
            (
                select attempt_count::text
                from event_purchase_application_fee_adjustment
                where event_purchase_application_fee_adjustment_id =
                    (item->>'event_purchase_application_fee_adjustment_id')::uuid
            ),
            item->>'event_purchase_application_fee_adjustment_id'
        from retry_claim
    $$,
    format($$ values ('2'::text, %L::text) $$, :'retryAdjustmentID'),
    'Should claim failed application-fee work as the next retry attempt'
);

-- Should reclaim an abandoned application-fee claim below the attempt limit
create temporary table stale_claim as
select claim_event_purchase_application_fee_adjustment('stripe') as item;
select results_eq(
    $$
        select
            (
                select attempt_count::text
                from event_purchase_application_fee_adjustment
                where event_purchase_application_fee_adjustment_id =
                    (item->>'event_purchase_application_fee_adjustment_id')::uuid
            ),
            item->>'event_purchase_application_fee_adjustment_id'
        from stale_claim
    $$,
    format($$ values ('2'::text, %L::text) $$, :'staleAdjustmentID'),
    'Should reclaim an abandoned application-fee claim below the attempt limit'
);

-- Should not reclaim an abandoned final automatic attempt
select is(
    claim_event_purchase_application_fee_adjustment('stripe'),
    null,
    'Should not reclaim an abandoned final automatic attempt'
);

-- Should surface an abandoned final application-fee attempt for operator action
select results_eq(
    format($$
        select attempt_count, claim_id, failure_message, status
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'finalAdjustmentID'),
    $$ values (
        10,
        null::uuid,
        E'provider timed out\nApplication-fee adjustment worker claim expired after the final automatic attempt; provider outcome is unknown'::text,
        'failed'::text
    ) $$,
    'Should surface an abandoned final application-fee attempt for operator action'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
