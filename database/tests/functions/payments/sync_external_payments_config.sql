-- Tests syncing the singleton external-payments configuration row.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should insert the singleton configuration row
select lives_ok(
    $$select sync_external_payments_config(array['kr', 'NG'], 72, 336)$$,
    'Should insert the singleton configuration row'
);

select results_eq(
    $$
        select
            allowed_countries,
            default_payment_window_hours,
            max_payment_window_hours
        from external_payments_config
    $$,
    $$
        values (
            array['KR', 'NG']::text[],
            72,
            336
        )
    $$,
    'Should insert the singleton configuration row'
);

-- Should replace the singleton configuration row
select lives_ok(
    $$select sync_external_payments_config(array['AR'], 48, 168)$$,
    'Should replace the singleton configuration row'
);

select results_eq(
    $$
        select
            allowed_countries,
            default_payment_window_hours,
            max_payment_window_hours,
            (select count(*) from external_payments_config)
        from external_payments_config
    $$,
    $$
        values (
            array['AR']::text[],
            48,
            168,
            1::bigint
        )
    $$,
    'Should replace the singleton configuration row'
);

-- Should delete the singleton row when the configuration is removed
select lives_ok(
    $$select sync_external_payments_config(null, null, null)$$,
    'Should delete the singleton row when the configuration is removed'
);

select is(
    (select count(*)::int from external_payments_config),
    0,
    'Should delete the singleton row when the configuration is removed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
