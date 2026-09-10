-- Tests country-level external-payments allowlisting.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Operator allowlist used by the country-allowlist scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report allowlisted for a matching country code
select is(
    is_country_external_payments_allowlisted('KR'),
    true,
    'Should report allowlisted for a matching country code'
);

-- Should ignore country-code case when checking the allowlist
select is(
    is_country_external_payments_allowlisted(' kr '),
    true,
    'Should ignore country-code case when checking the allowlist'
);

-- Should report unlisted for a country outside the allowlist
select is(
    is_country_external_payments_allowlisted('US'),
    false,
    'Should report unlisted for a country outside the allowlist'
);

-- Should report unlisted for a missing country code
select is(
    is_country_external_payments_allowlisted(null),
    false,
    'Should report unlisted for a missing country code'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
