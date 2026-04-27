-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept zero amounts for free tickets
select lives_ok(
    $$select validate_payment_amount('USD', 0)$$,
    'Should accept zero amounts for free tickets'
);

-- Should accept minimum amounts
select lives_ok(
    $$select validate_payment_amount('USD', 50)$$,
    'Should accept Stripe minimum amounts'
);

-- Should accept currency-specific minimum amounts
select lives_ok(
    $$select validate_payment_amount('JPY', 50)$$,
    'Should accept currency-specific Stripe minimum amounts'
);

-- Should accept currency-specific maximum amounts
select lives_ok(
    $$select validate_payment_amount('JPY', 9999999999999)$$,
    'Should accept currency-specific Stripe maximum amounts'
);

-- Should reject missing amounts
select throws_ok(
    $$select validate_payment_amount('USD', null)$$,
    'payment amount is required',
    'Should reject missing amounts'
);

-- Should reject negative amounts
select throws_ok(
    $$select validate_payment_amount('USD', -1)$$,
    'payment amount must be greater than or equal to 0',
    'Should reject negative amounts'
);

-- Should reject non-zero amounts below minimums
select throws_ok(
    $$select validate_payment_amount('USD', 49)$$,
    'payment amount must be zero or at least Stripe minimum charge amount',
    'Should reject non-zero amounts below Stripe minimums'
);

-- Should reject currency-specific amounts below minimums
select throws_ok(
    $$select validate_payment_amount('JPY', 49)$$,
    'payment amount must be zero or at least Stripe minimum charge amount',
    'Should reject currency-specific amounts below Stripe minimums'
);

-- Should reject amounts above maximums
select throws_ok(
    $$select validate_payment_amount('USD', 100000000)$$,
    'payment amount exceeds Stripe maximum charge amount',
    'Should reject amounts above Stripe maximums'
);

-- Should reject unsupported currencies
select throws_ok(
    $$select validate_payment_amount('USDD', 50)$$,
    'payment_currency_code must be a supported currency code',
    'Should reject unsupported currencies'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
