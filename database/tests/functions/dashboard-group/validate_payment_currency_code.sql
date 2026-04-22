-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept uppercase supported currencies
select lives_ok(
    $$select validate_payment_currency_code('USD')$$,
    'Should accept uppercase supported currencies'
);

-- Should accept lowercase supported currencies
select lives_ok(
    $$select validate_payment_currency_code('usd')$$,
    'Should accept lowercase supported currencies'
);

-- Should reject empty currencies
select throws_ok(
    $$select validate_payment_currency_code('   ')$$,
    'payment_currency_code cannot be empty',
    'Should reject empty currencies'
);

-- Should reject unsupported currencies
select throws_ok(
    $$select validate_payment_currency_code('USDD')$$,
    'payment_currency_code must be a supported currency code',
    'Should reject unsupported currencies'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
