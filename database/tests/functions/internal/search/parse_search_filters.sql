-- Tests parsing the shared search and list filters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should parse every shared key
select results_eq(
    $$
    select date_from, date_to, ilike_pattern, limit_value, offset_value, sort, ts_query, tsquery
    from parse_search_filters(jsonb_build_object(
        'date_from', '2024-01-01',
        'date_to', '2024-01-31',
        'limit', 25,
        'offset', 50,
        'sort', 'Created-Desc',
        'ts_query', '  Kube 50% '
    ))
    $$,
    $$
    values (
        '2024-01-01'::date,
        '2024-01-31'::date,
        '%Kube 50\%%',
        25,
        50,
        'created-desc',
        'Kube 50%',
        $q$'kube':* & '50':*$q$::tsquery
    )
    $$,
    'Should parse every shared key'
);

-- Should return nulls for missing keys
select results_eq(
    $$
    select date_from, date_to, ilike_pattern, limit_value, offset_value, sort, ts_query, tsquery
    from parse_search_filters('{}'::jsonb)
    $$,
    $$
    values (null::date, null::date, null::text, null::int, null::int, null::text, null::text, null::tsquery)
    $$,
    'Should return nulls for missing keys'
);

-- Should clamp negative pagination values to zero
select results_eq(
    $$ select limit_value, offset_value from parse_search_filters('{"limit": -10, "offset": -1}'::jsonb) $$,
    $$ values (0, 0) $$,
    'Should clamp negative pagination values to zero'
);

-- Should treat blank text as no query
select results_eq(
    $$ select ilike_pattern, sort, ts_query, tsquery from parse_search_filters('{"sort": " ", "ts_query": "   "}'::jsonb) $$,
    $$ values (null::text, null::text, null::text, null::tsquery) $$,
    'Should treat blank text as no query'
);

-- Should treat empty dates as unset
select results_eq(
    $$ select date_from, date_to from parse_search_filters('{"date_from": "", "date_to": ""}'::jsonb) $$,
    $$ values (null::date, null::date) $$,
    'Should treat empty dates as unset'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
