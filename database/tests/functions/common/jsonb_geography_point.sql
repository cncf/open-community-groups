-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should convert latitude and longitude fields to a geography point
select is(
    st_srid(jsonb_geography_point(jsonb_build_object('latitude', 37.7749, 'longitude', -122.4194))::geometry),
    4326,
    'Should use SRID 4326'
);

select is(
    st_y(jsonb_geography_point(jsonb_build_object('latitude', 37.7749, 'longitude', -122.4194))::geometry),
    37.7749::double precision,
    'Should preserve latitude'
);

select is(
    st_x(jsonb_geography_point(jsonb_build_object('latitude', 37.7749, 'longitude', -122.4194))::geometry),
    -122.4194::double precision,
    'Should preserve longitude'
);

-- Should return null when coordinates are absent
select ok(
    jsonb_geography_point(null) is null,
    'Should return null for SQL null'
);

select ok(
    jsonb_geography_point('null'::jsonb) is null,
    'Should return null for JSON null'
);

select ok(
    jsonb_geography_point(jsonb_build_object('longitude', -122.4194)) is null,
    'Should return null without latitude'
);

select ok(
    jsonb_geography_point(jsonb_build_object('latitude', 37.7749)) is null,
    'Should return null without longitude'
);

-- Should preserve current cast behavior for empty coordinate strings
select throws_ok(
    $$ select jsonb_geography_point(jsonb_build_object('latitude', '', 'longitude', -122.4194)) $$,
    '22P02',
    'invalid input syntax for type double precision: ""',
    'Should reject empty coordinate strings'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
