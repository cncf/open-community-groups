-- Tests projecting a durable refund row into the worker payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should project every refund field with epoch-encoded timestamps
select is(
    event_purchase_refund_to_json(jsonb_populate_record(null::event_purchase_refund, jsonb_build_object(
        'amount_minor', 2500,
        'attempt_count', 3,
        'claim_id', 'f2060000-0000-0000-0000-000000000001',
        'currency_code', 'USD',
        'event_purchase_id', 'f2060000-0000-0000-0000-000000000002',
        'event_purchase_refund_id', 'f2060000-0000-0000-0000-000000000003',
        'failure_message', 'provider timeout',
        'finalized_at', '2024-01-01 00:00:00+00',
        'idempotency_key', 'event-purchase-refund-to-json',
        'kind', 'refund-request-approval',
        'payment_provider_id', 'stripe',
        'provider_refund_id', 're_123',
        'provider_refunded_at', '2024-01-01 00:00:01+00',
        'status', 'finalized',
        'terminal_failure', false
    ))),
    jsonb_build_object(
        'amount_minor', 2500,
        'attempt_count', 3,
        'claim_id', 'f2060000-0000-0000-0000-000000000001',
        'currency_code', 'USD',
        'event_purchase_id', 'f2060000-0000-0000-0000-000000000002',
        'event_purchase_refund_id', 'f2060000-0000-0000-0000-000000000003',
        'failure_message', 'provider timeout',
        'finalized_at', 1704067200,
        'idempotency_key', 'event-purchase-refund-to-json',
        'kind', 'refund-request-approval',
        'payment_provider', 'stripe',
        'provider_refund_id', 're_123',
        'provider_refunded_at', 1704067201,
        'status', 'finalized',
        'terminal_failure', false
    ),
    'Should project every refund field with epoch-encoded timestamps'
);

-- Should strip null optional fields
select is(
    event_purchase_refund_to_json(jsonb_populate_record(null::event_purchase_refund, jsonb_build_object(
        'amount_minor', 100,
        'attempt_count', 0,
        'currency_code', 'EUR',
        'event_purchase_id', 'f2060000-0000-0000-0000-000000000004',
        'event_purchase_refund_id', 'f2060000-0000-0000-0000-000000000005',
        'idempotency_key', 'event-purchase-refund-to-json-pending',
        'kind', 'automatic-unfulfillable-checkout',
        'payment_provider_id', 'stripe',
        'status', 'provider-pending',
        'terminal_failure', false
    ))),
    jsonb_build_object(
        'amount_minor', 100,
        'attempt_count', 0,
        'currency_code', 'EUR',
        'event_purchase_id', 'f2060000-0000-0000-0000-000000000004',
        'event_purchase_refund_id', 'f2060000-0000-0000-0000-000000000005',
        'idempotency_key', 'event-purchase-refund-to-json-pending',
        'kind', 'automatic-unfulfillable-checkout',
        'payment_provider', 'stripe',
        'status', 'provider-pending',
        'terminal_failure', false
    ),
    'Should strip null optional fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
