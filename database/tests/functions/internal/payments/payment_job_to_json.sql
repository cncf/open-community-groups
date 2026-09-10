-- Tests projecting payment job lifecycle state to JSON.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should project required and optional lifecycle fields
select is(
    payment_job_to_json(jsonb_populate_record(null::payment_job, jsonb_build_object(
        'attempt_count', 3,
        'claim_id', 'd40e0000-0000-0000-0000-000000000001',
        'event_purchase_id', 'd40e0000-0000-0000-0000-000000000002',
        'failure_message', 'provider unavailable',
        'idempotency_key', 'payment-job-to-json-full-d40e0000',
        'kind', 'event-purchase-refund',
        'payment_job_id', 'd40e0000-0000-0000-0000-000000000003',
        'payment_provider_id', 'stripe',
        'status', 'processing'
    ))),
    jsonb_build_object(
        'attempt_count', 3,
        'event_purchase_id', 'd40e0000-0000-0000-0000-000000000002',
        'idempotency_key', 'payment-job-to-json-full-d40e0000',
        'kind', 'event-purchase-refund',
        'payment_job_id', 'd40e0000-0000-0000-0000-000000000003',
        'payment_provider', 'stripe',
        'status', 'processing',
        'claim_id', 'd40e0000-0000-0000-0000-000000000001',
        'failure_message', 'provider unavailable'
    ),
    'Should project required and optional lifecycle fields'
);

-- Should strip absent optional lifecycle fields
select is(
    payment_job_to_json(jsonb_populate_record(null::payment_job, jsonb_build_object(
        'attempt_count', 0,
        'event_purchase_id', 'd40e0000-0000-0000-0000-000000000004',
        'idempotency_key', 'payment-job-to-json-minimal-d40e0000',
        'kind', 'event-purchase-credit-note',
        'payment_job_id', 'd40e0000-0000-0000-0000-000000000005',
        'payment_provider_id', 'stripe',
        'status', 'pending'
    ))),
    jsonb_build_object(
        'attempt_count', 0,
        'event_purchase_id', 'd40e0000-0000-0000-0000-000000000004',
        'idempotency_key', 'payment-job-to-json-minimal-d40e0000',
        'kind', 'event-purchase-credit-note',
        'payment_job_id', 'd40e0000-0000-0000-0000-000000000005',
        'payment_provider', 'stripe',
        'status', 'pending'
    ),
    'Should strip absent optional lifecycle fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
