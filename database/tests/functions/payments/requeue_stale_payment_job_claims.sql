-- Tests recovering stale payment job claims.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cappedClaimID 'd4150000-0000-0000-0000-000000000001'
\set cappedJobID 'd4150000-0000-0000-0000-000000000002'
\set communityID 'd4150000-0000-0000-0000-000000000003'
\set eventCategoryID 'd4150000-0000-0000-0000-000000000004'
\set eventID 'd4150000-0000-0000-0000-000000000005'
\set failedJobID 'd4150000-0000-0000-0000-000000000006'
\set groupCategoryID 'd4150000-0000-0000-0000-000000000007'
\set groupID 'd4150000-0000-0000-0000-000000000008'
\set priorClaimID 'd4150000-0000-0000-0000-000000000009'
\set priorJobID 'd4150000-0000-0000-0000-000000000010'
\set purchaseID 'd4150000-0000-0000-0000-000000000011'
\set recentClaimID 'd4150000-0000-0000-0000-000000000012'
\set recentJobID 'd4150000-0000-0000-0000-000000000013'
\set staleClaimID 'd4150000-0000-0000-0000-000000000014'
\set staleJobID 'd4150000-0000-0000-0000-000000000015'
\set ticketTypeID 'd4150000-0000-0000-0000-000000000016'
\set userID 'd4150000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with stale claim recovery jobs
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by the purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Purchase owning all stale claim jobs
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_charge_id, provider_checkout_session_id,
    provider_object_account_id, provider_payment_reference,
    provider_total_minor, provisional_platform_fee_amount_minor,
    seller_snapshot, status, subtotal_excluding_tax_minor, tax_amount_minor,
    tax_behavior, tax_calculation_mode, tax_classification, ticket_title,
    user_id, venue_snapshot
) values (
    2500, 'direct-charge', 'acct_d415', 'USD', :'eventID', :'purchaseID',
    :'ticketTypeID', 80, 'stripe', 'ch_stale_claims_d4150000',
    'cs_stale_claims_d4150000', 'acct_d415', 'pi_stale_claims_d4150000',
    2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'userID', '{}'::jsonb
);

-- Final-attempt processing job with existing provider diagnostics
insert into payment_job (
    attempt_count, claim_id, claimed_at, event_purchase_id, failure_message,
    idempotency_key, kind, next_attempt_at, payment_job_id,
    payment_provider_id, status
) values (
    10, :'cappedClaimID', current_timestamp - interval '16 minutes',
    :'purchaseID', 'provider timed out',
    'requeue-stale-payment-job-claims-capped-d4150000',
    'event-purchase-refund', '2024-01-01 00:00:00+00', :'cappedJobID',
    'stripe', 'processing'
);

-- Failed job that is not currently claimed
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    next_attempt_at, payment_job_id, payment_provider_id, status
) values (
    2, :'purchaseID', 'retry later',
    'requeue-stale-payment-job-claims-failed-d4150000',
    'event-purchase-refund', '2024-01-01 00:00:00+00', :'failedJobID',
    'stripe', 'failed'
);

-- Stale processing job with an existing failure message below the cap
insert into payment_job (
    attempt_count, claim_id, claimed_at, event_purchase_id, failure_message,
    idempotency_key, kind, next_attempt_at, payment_job_id,
    payment_provider_id, status
) values (
    3, :'priorClaimID', current_timestamp - interval '16 minutes',
    :'purchaseID', 'provider unavailable',
    'requeue-stale-payment-job-claims-prior-d4150000',
    'event-purchase-refund', '2024-01-01 00:00:00+00', :'priorJobID',
    'stripe', 'processing'
);

-- Recent processing job that remains claimed
insert into payment_job (
    attempt_count, claim_id, claimed_at, event_purchase_id, idempotency_key,
    kind, next_attempt_at, payment_job_id, payment_provider_id, status
) values (
    2, :'recentClaimID', current_timestamp - interval '14 minutes',
    :'purchaseID', 'requeue-stale-payment-job-claims-recent-d4150000',
    'event-purchase-refund', '2024-01-01 00:00:00+00', :'recentJobID',
    'stripe', 'processing'
);

-- Stale processing job without a prior failure message below the cap
insert into payment_job (
    attempt_count, claim_id, claimed_at, event_purchase_id, idempotency_key,
    kind, next_attempt_at, payment_job_id, payment_provider_id, status
) values (
    2, :'staleClaimID', current_timestamp - interval '16 minutes',
    :'purchaseID', 'requeue-stale-payment-job-claims-stale-d4150000',
    'event-purchase-refund', '2024-01-01 00:00:00+00', :'staleJobID',
    'stripe', 'processing'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release every payment job claim older than the processing timeout
select is(
    requeue_stale_payment_job_claims(),
    3,
    'Should release every payment job claim older than the processing timeout'
);

-- Should leave recent and non-processing payment jobs unchanged
select results_eq(
    format($$
        select payment_job_id, claim_id, failure_message, status
        from payment_job
        where payment_job_id in (%L::uuid, %L::uuid)
        order by payment_job_id
    $$, :'failedJobID', :'recentJobID'),
    format($$ values
        (%L::uuid, null::uuid, 'retry later'::text, 'failed'::text),
        (%L::uuid, %L::uuid, null::text, 'processing'::text)
    $$, :'failedJobID', :'recentJobID', :'recentClaimID'),
    'Should leave recent and non-processing payment jobs unchanged'
);

-- Should preserve an existing failure below the attempt limit
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message,
            next_attempt_at = current_timestamp, status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'priorJobID'),
    $$ values (
        null::uuid,
        null::timestamptz,
        'provider unavailable'::text,
        true,
        'failed'::text
    ) $$,
    'Should preserve an existing failure below the attempt limit'
);

-- Should preserve final-attempt schedule while appending recovery notice
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message, next_attempt_at, status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'cappedJobID'),
    $$ values (
        null::uuid,
        null::timestamptz,
        E'provider timed out\npayment job claim expired after the final automatic attempt; provider outcome is unknown'::text,
        '2024-01-01 00:00:00+00'::timestamptz,
        'failed'::text
    ) $$,
    'Should preserve final-attempt schedule while appending recovery notice'
);

-- Should record worker expiration below the attempt limit
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message,
            next_attempt_at = current_timestamp, status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'staleJobID'),
    $$ values (
        null::uuid,
        null::timestamptz,
        'payment job claim expired'::text,
        true,
        'failed'::text
    ) $$,
    'Should record worker expiration below the attempt limit'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
