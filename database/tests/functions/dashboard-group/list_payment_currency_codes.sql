-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return three-letter uppercase currency codes
select ok(
    (select bool_and(code ~ '^[A-Z]{3}$') from unnest(list_payment_currency_codes()) code),
    'Should return three-letter uppercase currency codes'
);

-- Should return currencies sorted alphabetically without duplicates
select is(
    list_payment_currency_codes(),
    (select array_agg(code order by code) from (select distinct code from unnest(list_payment_currency_codes()) code) codes),
    'Should return currencies sorted alphabetically without duplicates'
);

-- Should include common currencies for dashboard usage
select ok(
    array['EUR', 'GBP', 'USD']::text[] <@ list_payment_currency_codes(),
    'Should include common currencies'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
