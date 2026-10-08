-- Tests building the bounding box envelope of search filters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should build the envelope when all bbox keys are present
select is(
    st_asewkt(search_bbox_envelope(jsonb_build_object(
        'bbox_ne_lat', 40.5,
        'bbox_ne_lon', -3.25,
        'bbox_sw_lat', 40.25,
        'bbox_sw_lon', -3.5
    ))),
    'SRID=4326;POLYGON((-3.5 40.25,-3.5 40.5,-3.25 40.5,-3.25 40.25,-3.5 40.25))',
    'Should build the envelope when all bbox keys are present'
);

-- Should return null when a bbox key is missing
select is(
    search_bbox_envelope(jsonb_build_object(
        'bbox_ne_lat', 40.5,
        'bbox_ne_lon', -3.25,
        'bbox_sw_lat', 40.25
    )),
    null,
    'Should return null when a bbox key is missing'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
