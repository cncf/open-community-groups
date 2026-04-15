-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the expected number of supported currencies
select is(
    array_length(list_payment_currency_codes(), 1),
    135,
    'Should return the expected number of supported currencies'
);

-- Should return currencies sorted alphabetically
select is(
    (list_payment_currency_codes())[1],
    'AED',
    'Should start with the alphabetically first supported currency'
);

-- Should include USD for common dashboard usage
select ok(
    'USD' = any(list_payment_currency_codes()),
    'Should include USD'
);

-- Should reject typos by omitting unsupported codes
select ok(
    not ('USDD' = any(list_payment_currency_codes())),
    'Should not include unsupported currency codes'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
