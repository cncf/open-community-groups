-- Tests parsing the explore filters shared by the search matchers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e2e20000-0000-0000-0000-000000000001'
\set communityOtherID 'e2e20000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community selected by name
select fx_community(:'communityID', jsonb_build_object('name', 'pef-community'));

-- Second community selected by name
select fx_community(:'communityOtherID', jsonb_build_object('name', 'pef-other-community'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore the distance without both coordinates
select results_eq(
    $$
        select max_distance, user_location
        from parse_explore_filters('{"distance": 1000, "latitude": 40.7128}'::jsonb)
    $$,
    $$ values (null::real, null::geography) $$,
    'Should ignore the distance without both coordinates'
);

-- Should leave the location null unless both coordinates are present
select results_eq(
    $$
        select user_location from parse_explore_filters('{"latitude": 40.7128}'::jsonb)
        union all
        select user_location from parse_explore_filters('{"longitude": -74.0060}'::jsonb)
    $$,
    $$ values (null::geography), (null::geography) $$,
    'Should leave the location null unless both coordinates are present'
);

-- Should lowercase group categories and regions
select results_eq(
    $$
        select group_category, region
        from parse_explore_filters('{
            "group_category": ["PEF-Business", "pef-tech"],
            "region": ["PEF-North-America"]
        }'::jsonb)
    $$,
    $$ values (array['pef-business', 'pef-tech']::text[], array['pef-north-america']::text[]) $$,
    'Should lowercase group categories and regions'
);

-- Should match all communities when the community selection is empty
select is(
    (select community_ids from parse_explore_filters('{"community": []}'::jsonb)),
    null::uuid[],
    'Should match all communities when the community selection is empty'
);

-- Should match nothing for an unknown community
select is(
    (select community_ids from parse_explore_filters('{"community": ["pef-unknown-community"]}'::jsonb)),
    array[]::uuid[],
    'Should match nothing for an unknown community'
);

-- Should parse the viewer location and maximum distance
select results_eq(
    $$
        select max_distance, st_astext(user_location::geometry)
        from parse_explore_filters('{
            "distance": 1000,
            "latitude": 40.7128,
            "longitude": -74.0060
        }'::jsonb)
    $$,
    $$ values (1000::real, 'POINT(-74.006 40.7128)') $$,
    'Should parse the viewer location and maximum distance'
);

-- Should resolve community names to ids
select set_eq(
    $$
        select unnest(community_ids)
        from parse_explore_filters('{
            "community": ["pef-community", "pef-other-community", "pef-unknown-community"]
        }'::jsonb)
    $$,
    array[:'communityID', :'communityOtherID']::uuid[],
    'Should resolve community names to ids'
);

-- Should return nulls for absent keys
select results_eq(
    $$
        select community_ids, group_category, max_distance, region, user_location
        from parse_explore_filters('{}'::jsonb)
    $$,
    $$ values (null::uuid[], null::text[], null::real, null::text[], null::geography) $$,
    'Should return nulls for absent keys'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
