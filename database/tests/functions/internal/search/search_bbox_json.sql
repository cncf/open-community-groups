-- Tests encoding a search extent as bounding box JSON.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should encode the corners of the extent
select is(
    search_bbox_json(st_makeenvelope(-3.5, 40.25, -3.25, 40.5, 4326))::jsonb,
    jsonb_build_object(
        'ne_lat', 40.5,
        'ne_lon', -3.25,
        'sw_lat', 40.25,
        'sw_lon', -3.5
    ),
    'Should encode the corners of the extent'
);

-- Should return null when there is no extent
select is(
    search_bbox_json(null)::jsonb,
    null,
    'Should return null when there is no extent'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
