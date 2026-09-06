-- Tests administrator requeueing of exhausted payment jobs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd4140000-0000-0000-0000-000000000001'
\set eventCategoryID 'd4140000-0000-0000-0000-000000000002'
\set eventID 'd4140000-0000-0000-0000-000000000003'
\set failedJobID 'd4140000-0000-0000-0000-000000000004'
\set failedPurchaseID 'd4140000-0000-0000-0000-000000000005'
\set failedRefundID 'd4140000-0000-0000-0000-000000000006'
\set groupCategoryID 'd4140000-0000-0000-0000-000000000007'
\set groupID 'd4140000-0000-0000-0000-000000000008'
\set lowJobID 'd4140000-0000-0000-0000-000000000009'
\set lowPurchaseID 'd4140000-0000-0000-0000-000000000010'
\set lowRefundID 'd4140000-0000-0000-0000-000000000011'
\set missingGroupID 'd4140000-0000-0000-0000-000000000012'
\set missingJobID 'd4140000-0000-0000-0000-000000000013'
\set pendingJobID 'd4140000-0000-0000-0000-000000000014'
\set pendingPurchaseID 'd4140000-0000-0000-0000-000000000015'
\set pendingRefundID 'd4140000-0000-0000-0000-000000000016'
\set scopeJobID 'd4140000-0000-0000-0000-000000000017'
\set scopePurchaseID 'd4140000-0000-0000-0000-000000000018'
\set scopeRefundID 'd4140000-0000-0000-0000-000000000019'
\set terminalJobID 'd4140000-0000-0000-0000-000000000020'
\set terminalPurchaseID 'd4140000-0000-0000-0000-000000000021'
\set terminalRefundID 'd4140000-0000-0000-0000-000000000022'
\set ticketTypeID 'd4140000-0000-0000-0000-000000000023'
\set userID 'd4140000-0000-0000-0000-000000000024'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with administrator requeue purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type referenced by every administrator requeue purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General admission'
));

-- Purchases backing retryable, ineligible, terminal, and scope fixtures
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_charge_id, provider_checkout_session_id,
    provider_object_account_id, provider_payment_reference,
    provider_total_minor, provisional_platform_fee_amount_minor,
    seller_snapshot, status, subtotal_excluding_tax_minor, tax_amount_minor,
    tax_behavior, tax_calculation_mode, tax_classification, ticket_title,
    user_id, venue_snapshot
) values
    (2500, 'direct-charge', 'acct_d414', 'USD', :'eventID', :'failedPurchaseID', :'ticketTypeID', 80, 'stripe', 'ch_failed_requeue_d4140000', 'cs_failed_requeue_d4140000', 'acct_d414', 'pi_failed_requeue_d4140000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d414', 'USD', :'eventID', :'lowPurchaseID', :'ticketTypeID', 80, 'stripe', 'ch_low_requeue_d4140000', 'cs_low_requeue_d4140000', 'acct_d414', 'pi_low_requeue_d4140000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d414', 'USD', :'eventID', :'pendingPurchaseID', :'ticketTypeID', 80, 'stripe', 'ch_pending_requeue_d4140000', 'cs_pending_requeue_d4140000', 'acct_d414', 'pi_pending_requeue_d4140000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d414', 'USD', :'eventID', :'scopePurchaseID', :'ticketTypeID', 80, 'stripe', 'ch_scope_requeue_d4140000', 'cs_scope_requeue_d4140000', 'acct_d414', 'pi_scope_requeue_d4140000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d414', 'USD', :'eventID', :'terminalPurchaseID', :'ticketTypeID', 80, 'stripe', 'ch_terminal_requeue_d4140000', 'cs_terminal_requeue_d4140000', 'acct_d414', 'pi_terminal_requeue_d4140000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refund-recovery-pending', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb);

-- Exhausted failed refund job ready for an administrator retry
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    next_attempt_at, payment_job_id, payment_provider_id, status
) values (
    10, :'failedPurchaseID', 'provider unavailable',
    'requeue-payment-job-failed-d4140000', 'event-purchase-refund',
    '2099-01-01 00:00:00+00', :'failedJobID', 'stripe', 'failed'
);

-- Failed refund job that has not exhausted automatic retries
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    next_attempt_at, payment_job_id, payment_provider_id, status
) values (
    9, :'lowPurchaseID', 'provider unavailable',
    'requeue-payment-job-low-d4140000', 'event-purchase-refund',
    '2099-01-01 00:00:00+00', :'lowJobID', 'stripe', 'failed'
);

-- Exhausted pending refund job ready for an administrator retry
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    next_attempt_at, payment_job_id, payment_provider_id, status
) values (
    10, :'pendingPurchaseID', 'provider unavailable',
    'requeue-payment-job-pending-d4140000', 'event-purchase-refund',
    '2099-01-01 00:00:00+00', :'pendingJobID', 'stripe', 'pending'
);

-- Exhausted refund job used by the cross-group rejection
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    next_attempt_at, payment_job_id, payment_provider_id, status
) values (
    10, :'scopePurchaseID', 'provider unavailable',
    'requeue-payment-job-scope-d4140000', 'event-purchase-refund',
    '2099-01-01 00:00:00+00', :'scopeJobID', 'stripe', 'failed'
);

-- Exhausted refund job blocked by terminal provider failure
insert into payment_job (
    attempt_count, event_purchase_id, failure_message, idempotency_key, kind,
    next_attempt_at, payment_job_id, payment_provider_id, status
) values (
    10, :'terminalPurchaseID', 'terminal failure',
    'requeue-payment-job-terminal-d4140000', 'event-purchase-refund',
    '2099-01-01 00:00:00+00', :'terminalJobID', 'stripe', 'failed'
);

-- Refund in retryable failed provider state
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, status, terminal_failure
) values (
    2500, 'USD', :'failedPurchaseID', :'failedRefundID',
    'event-cancellation', :'failedJobID', 'stripe', 'provider-failed',
    false
);

-- Refund before its automatic retries are exhausted
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, status, terminal_failure
) values (
    2500, 'USD', :'lowPurchaseID', :'lowRefundID', 'event-cancellation',
    :'lowJobID', 'stripe', 'provider-failed', false
);

-- Refund in pending provider state after automatic exhaustion
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, status, terminal_failure
) values (
    2500, 'USD', :'pendingPurchaseID', :'pendingRefundID',
    'event-cancellation', :'pendingJobID', 'stripe', 'provider-pending',
    false
);

-- Refund outside the requested group scope
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, status, terminal_failure
) values (
    2500, 'USD', :'scopePurchaseID', :'scopeRefundID', 'event-cancellation',
    :'scopeJobID', 'stripe', 'provider-failed', false
);

-- Terminal refund that cannot be retried automatically
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, provider_refund_id, status,
    terminal_failure
) values (
    2500, 'USD', :'terminalPurchaseID', :'terminalRefundID',
    'event-cancellation', :'terminalJobID', 'stripe',
    're_terminal_requeue_d4140000', 'provider-failed', true
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should requeue an exhausted failed payment job
select lives_ok(
    format(
        $$select requeue_payment_job(%L::uuid, %L::uuid)$$,
        :'groupID', :'failedJobID'
    ),
    'Should requeue an exhausted failed payment job'
);
select results_eq(
    format($$
        select
            attempt_count,
            failure_message,
            next_attempt_at = current_timestamp, status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'failedJobID'),
    $$ values (0, null::text, true, 'pending'::text) $$,
    'Should persist an exhausted failed payment job requeue'
);

-- Should requeue an exhausted pending payment job
select lives_ok(
    format(
        $$select requeue_payment_job(%L::uuid, %L::uuid)$$,
        :'groupID', :'pendingJobID'
    ),
    'Should requeue an exhausted pending payment job'
);
select results_eq(
    format($$
        select
            attempt_count,
            failure_message,
            next_attempt_at = current_timestamp, status
        from payment_job
        where payment_job_id = %L::uuid
    $$, :'pendingJobID'),
    $$ values (0, null::text, true, 'pending'::text) $$,
    'Should persist an exhausted pending payment job requeue'
);

-- Should reject a missing payment job
select throws_ok(
    format(
        $$select requeue_payment_job(%L::uuid, %L::uuid)$$,
        :'groupID', :'missingJobID'
    ),
    'OCG01',
    'retryable payment job not found',
    'Should reject a missing payment job'
);

-- Should reject a payment job outside the requested group
select throws_ok(
    format(
        $$select requeue_payment_job(%L::uuid, %L::uuid)$$,
        :'missingGroupID', :'scopeJobID'
    ),
    'OCG01',
    'retryable payment job not found',
    'Should reject a payment job outside the requested group'
);

-- Should reject a payment job before automatic retries are exhausted
select throws_ok(
    format(
        $$select requeue_payment_job(%L::uuid, %L::uuid)$$,
        :'groupID', :'lowJobID'
    ),
    'OCG01',
    'retryable payment job not found',
    'Should reject a payment job before automatic retries are exhausted'
);

-- Should reject a terminal refund payment job
select throws_ok(
    format(
        $$select requeue_payment_job(%L::uuid, %L::uuid)$$,
        :'groupID', :'terminalJobID'
    ),
    'OCG01',
    'retryable payment job not found',
    'Should reject a terminal refund payment job'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
