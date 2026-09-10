-- Tests recording retryable payment job failures.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set blankClaimID 'd4130000-0000-0000-0000-000000000001'
\set blankJobID 'd4130000-0000-0000-0000-000000000002'
\set cappedClaimID 'd4130000-0000-0000-0000-000000000003'
\set cappedJobID 'd4130000-0000-0000-0000-000000000004'
\set communityID 'd4130000-0000-0000-0000-000000000005'
\set eventCategoryID 'd4130000-0000-0000-0000-000000000006'
\set eventID 'd4130000-0000-0000-0000-000000000007'
\set groupCategoryID 'd4130000-0000-0000-0000-000000000008'
\set groupID 'd4130000-0000-0000-0000-000000000009'
\set normalClaimID 'd4130000-0000-0000-0000-000000000010'
\set normalJobID 'd4130000-0000-0000-0000-000000000011'
\set purchaseID 'd4130000-0000-0000-0000-000000000012'
\set staleClaimID 'd4130000-0000-0000-0000-000000000013'
\set staleJobID 'd4130000-0000-0000-0000-000000000014'
\set ticketTypeID 'd4130000-0000-0000-0000-000000000015'
\set userID 'd4130000-0000-0000-0000-000000000016'
\set wrongClaimID 'd4130000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with failure-recording jobs
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by the purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Purchase owning all payment jobs under failure recording
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
    2500, 'direct-charge', 'acct_d413', 'USD', :'eventID', :'purchaseID',
    :'ticketTypeID', 80, 'stripe', 'ch_failure_d4130000',
    'cs_failure_d4130000', 'acct_d413', 'pi_failure_d4130000', 2500, 100,
    '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive',
    'manual', 'professional-event-admission', 'General admission', :'userID',
    '{}'::jsonb
);

-- Processing payment job that receives the default failure message
insert into payment_job (
    attempt_count, claim_id, claimed_at, event_purchase_id, idempotency_key,
    kind, payment_job_id, payment_provider_id, status
) values (
    2, :'blankClaimID', current_timestamp, :'purchaseID',
    'record-payment-job-failure-blank-d4130000', 'event-purchase-refund',
    :'blankJobID', 'stripe', 'processing'
);

-- Processing payment job whose retry delay is capped
insert into payment_job (
    attempt_count, claim_id, claimed_at, event_purchase_id, idempotency_key,
    kind, payment_job_id, payment_provider_id, status
) values (
    7, :'cappedClaimID', current_timestamp, :'purchaseID',
    'record-payment-job-failure-capped-d4130000', 'event-purchase-refund',
    :'cappedJobID', 'stripe', 'processing'
);

-- Processing payment job that records a normalized provider message
insert into payment_job (
    attempt_count, claim_id, claimed_at, event_purchase_id, idempotency_key,
    kind, payment_job_id, payment_provider_id, status
) values (
    1, :'normalClaimID', current_timestamp, :'purchaseID',
    'record-payment-job-failure-normal-d4130000', 'event-purchase-refund',
    :'normalJobID', 'stripe', 'processing'
);

-- Processing payment job held by a different claim
insert into payment_job (
    attempt_count, claim_id, claimed_at, event_purchase_id, idempotency_key,
    kind, payment_job_id, payment_provider_id, status
) values (
    1, :'staleClaimID', current_timestamp, :'purchaseID',
    'record-payment-job-failure-stale-d4130000', 'event-purchase-refund',
    :'staleJobID', 'stripe', 'processing'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release a claimed payment job with normalized failure state
select lives_ok(
    format(
        $$select record_payment_job_failure(%L::uuid, %L::uuid, '  provider unavailable  ')$$,
        :'normalJobID', :'normalClaimID'
    ),
    'Should release a claimed payment job with normalized failure state'
);
select results_eq(
    format($$
        select
            claim_id,
            claimed_at,
            failure_message,
            next_attempt_at = current_timestamp + interval '1 minute',
            status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'normalJobID'),
    $$ values (
        null::uuid,
        null::timestamptz,
        'provider unavailable'::text,
        true,
        'failed'::text
    ) $$,
    'Should persist a claimed payment job with normalized failure state'
);

-- Should default a blank payment job failure message
select lives_ok(
    format(
        $$select record_payment_job_failure(%L::uuid, %L::uuid, '   ')$$,
        :'blankJobID', :'blankClaimID'
    ),
    'Should default a blank payment job failure message'
);
select results_eq(
    format($$
        select
            failure_message,
            next_attempt_at = current_timestamp + interval '2 minutes'
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'blankJobID'),
    $$ values ('payment job attempt failed'::text, true) $$,
    'Should persist the default payment job failure message'
);

-- Should cap payment job retry backoff at thirty minutes
select lives_ok(
    format(
        $$select record_payment_job_failure(%L::uuid, %L::uuid, 'provider unavailable')$$,
        :'cappedJobID', :'cappedClaimID'
    ),
    'Should cap payment job retry backoff at thirty minutes'
);
select results_eq(
    format($$
        select next_attempt_at = current_timestamp + interval '30 minutes'
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'cappedJobID'),
    $$ values (true) $$,
    'Should persist capped payment job retry backoff'
);

-- Should reject a stale payment job claim
select throws_ok(
    format(
        $$select record_payment_job_failure(%L::uuid, %L::uuid, 'failure')$$,
        :'staleJobID', :'wrongClaimID'
    ),
    'payment job claim is stale',
    'Should reject a stale payment job claim'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
