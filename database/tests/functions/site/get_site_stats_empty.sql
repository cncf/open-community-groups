-- Tests site statistics on a database without countable rows.
-- Split from get_site_stats.sql because these scenarios require an empty
-- database, which contradicts the base file's seed data.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return empty series for every domain
select is(
    (
        select jsonb_build_object(
            'attendees', jsonb_build_array(stats->'attendees'->'per_month', stats->'attendees'->'running_total'),
            'events', jsonb_build_array(stats->'events'->'per_month', stats->'events'->'running_total'),
            'groups', jsonb_build_array(stats->'groups'->'per_month', stats->'groups'->'running_total'),
            'members', jsonb_build_array(stats->'members'->'per_month', stats->'members'->'running_total')
        )
        from (select get_site_stats()::jsonb as stats) site_stats
    ),
    '{
        "attendees": [[], []],
        "events": [[], []],
        "groups": [[], []],
        "members": [[], []]
    }'::jsonb,
    'Should return empty series for every domain'
);

-- Should return zero totals for every domain
select is(
    (
        select jsonb_build_object(
            'attendees', stats->'attendees'->'total',
            'events', stats->'events'->'total',
            'groups', stats->'groups'->'total',
            'members', stats->'members'->'total'
        )
        from (select get_site_stats()::jsonb as stats) site_stats
    ),
    '{"attendees": 0, "events": 0, "groups": 0, "members": 0}'::jsonb,
    'Should return zero totals for every domain'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
