-- Tests validating the attempt identifiers reported with a provider refund result.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a non-blank idempotency key and provider refund id
select lives_ok(
    $$select validate_event_purchase_refund_result('event-purchase-refund-key', 're_123')$$,
    'Should accept a non-blank idempotency key and provider refund id'
);

-- Should check the idempotency key before the provider refund id
select throws_ok(
    $$select validate_event_purchase_refund_result('', '')$$,
    'P0001',
    'expected idempotency key is required',
    'Should check the idempotency key before the provider refund id'
);

-- Should reject a blank expected idempotency key
select throws_ok(
    $$select validate_event_purchase_refund_result('   ', 're_123')$$,
    'P0001',
    'expected idempotency key is required',
    'Should reject a blank expected idempotency key'
);

-- Should reject a blank provider refund id
select throws_ok(
    $$select validate_event_purchase_refund_result('event-purchase-refund-key', '   ')$$,
    'P0001',
    'provider refund id is required',
    'Should reject a blank provider refund id'
);

-- Should reject an empty expected idempotency key
select throws_ok(
    $$select validate_event_purchase_refund_result('', 're_123')$$,
    'P0001',
    'expected idempotency key is required',
    'Should reject an empty expected idempotency key'
);

-- Should reject an empty provider refund id
select throws_ok(
    $$select validate_event_purchase_refund_result('event-purchase-refund-key', '')$$,
    'P0001',
    'provider refund id is required',
    'Should reject an empty provider refund id'
);

-- Should reject a null expected idempotency key
select throws_ok(
    $$select validate_event_purchase_refund_result(null, 're_123')$$,
    'P0001',
    'expected idempotency key is required',
    'Should reject a null expected idempotency key'
);

-- Should reject a null provider refund id
select throws_ok(
    $$select validate_event_purchase_refund_result('event-purchase-refund-key', null)$$,
    'P0001',
    'provider refund id is required',
    'Should reject a null provider refund id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
