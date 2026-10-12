-- Tests matching groups against search filters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(16);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5ea80000-0000-0000-0000-000000000001'
\set communityInactiveID '5ea80000-0000-0000-0000-000000000002'
\set communityOtherID '5ea80000-0000-0000-0000-000000000003'
\set groupAustinID '5ea80000-0000-0000-0000-000000000004'
\set groupCategoryBusinessID '5ea80000-0000-0000-0000-000000000005'
\set groupCategoryID '5ea80000-0000-0000-0000-000000000006'
\set groupCategoryInactiveID '5ea80000-0000-0000-0000-000000000007'
\set groupCategoryOtherID '5ea80000-0000-0000-0000-000000000008'
\set groupDeletedID '5ea80000-0000-0000-0000-000000000009'
\set groupInactiveCommunityID '5ea80000-0000-0000-0000-00000000000a'
\set groupInactiveID '5ea80000-0000-0000-0000-00000000000b'
\set groupLondonID '5ea80000-0000-0000-0000-00000000000c'
\set groupNewYorkID '5ea80000-0000-0000-0000-00000000000d'
\set groupOtherID '5ea80000-0000-0000-0000-00000000000e'
\set groupSanFranciscoID '5ea80000-0000-0000-0000-00000000000f'
\set regionID '5ea80000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community searched by name
select fx_community(:'communityID', jsonb_build_object('name', 'sgm-community'));

-- Inactive community whose groups never match
select fx_community(:'communityInactiveID', jsonb_build_object(
    'active', false,
    'name', 'sgm-inactive-community'
));

-- Second active community
select fx_community(:'communityOtherID', jsonb_build_object('name', 'sgm-other-community'));

-- Group category used by group-category filtering
select fx_group_category(:'groupCategoryBusinessID', :'communityID', jsonb_build_object(
    'name', 'SGM Business'
));

-- Group category used by groups outside the category filter
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category in the inactive community
select fx_group_category(:'groupCategoryInactiveID', :'communityInactiveID');

-- Group category in the second community
select fx_group_category(:'groupCategoryOtherID', :'communityOtherID');

-- Region used by region filtering
insert into region (region_id, community_id, name)
values (:'regionID', :'communityID', 'SGM North America');

-- Group in Austin within the region
select fx_group(:'groupAustinID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-97.7431 30.2672)'),
    'name', 'SGM Tech Innovators',
    'region_id', :'regionID',
    'slug', 'sgm-group-austin'
));

-- Deleted group in Seattle
select fx_group(:'groupDeletedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'location', ST_GeogFromText('POINT(-122.3321 47.6062)'),
    'name', 'SGM Deleted Group',
    'slug', 'sgm-group-deleted'
));

-- Group in the inactive community
select fx_group(:'groupInactiveCommunityID', :'communityInactiveID', :'groupCategoryInactiveID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-104.9903 39.7392)'),
    'name', 'SGM Inactive Community Group',
    'slug', 'sgm-group-inactive-community'
));

-- Inactive group in Miami
select fx_group(:'groupInactiveID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'location', ST_GeogFromText('POINT(-80.1918 25.7617)'),
    'name', 'SGM Archived Group',
    'slug', 'sgm-group-inactive'
));

-- Business group in London outside the region
select fx_group(:'groupLondonID', :'communityID', :'groupCategoryBusinessID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-0.1278 51.5074)'),
    'name', 'SGM Business Leaders',
    'slug', 'sgm-group-london'
));

-- Group in New York within the region, tagged for text search
select fx_group(:'groupNewYorkID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-74.0060 40.7128)'),
    'name', 'SGM Container Users',
    'region_id', :'regionID',
    'slug', 'sgm-group-ny',
    'tags', array['docker']
));

-- Group in Chicago in the second community
select fx_group(:'groupOtherID', :'communityOtherID', :'groupCategoryOtherID', jsonb_build_object(
    'active', true,
    'created_at', '2040-01-05 10:00:00+00',
    'location', ST_GeogFromText('POINT(-87.6298 41.8781)'),
    'name', 'SGM Python Developers',
    'slug', 'sgm-group-other'
));

-- Group in San Francisco within the region
select fx_group(:'groupSanFranciscoID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-122.4194 37.7749)'),
    'name', 'SGM Kubernetes Meetup',
    'region_id', :'regionID',
    'slug', 'sgm-group-sf'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should compute distances from the group location when sorting by distance
select results_eq(
    $$
        select group_id, round(distance)
        from search_groups_matches('{
            "latitude": 40.7128,
            "longitude": -74.0060,
            "region": ["SGM-North-America"],
            "sort_by": "distance"
        }'::jsonb)
        order by group_id
    $$,
    format(
        $$
            values
                (%L::uuid, round(st_distance(
                    'POINT(-97.7431 30.2672)'::geography,
                    'POINT(-74.0060 40.7128)'::geography
                ))),
                (%L::uuid, 0::double precision),
                (%L::uuid, round(st_distance(
                    'POINT(-122.4194 37.7749)'::geography,
                    'POINT(-74.0060 40.7128)'::geography
                )))
        $$,
        :'groupAustinID',
        :'groupNewYorkID',
        :'groupSanFranciscoID'
    ),
    'Should compute distances from the group location when sorting by distance'
);

-- Should exclude deleted groups when include_inactive is enabled
select ok(
    not exists (
        select 1
        from search_groups_matches('{"include_inactive": true}'::jsonb)
        where group_id = :'groupDeletedID'
    ),
    'Should exclude deleted groups when include_inactive is enabled'
);

-- Should exclude groups from inactive communities even when include_inactive is enabled
select ok(
    not exists (
        select 1
        from search_groups_matches('{
            "community": ["sgm-inactive-community"],
            "include_inactive": true
        }'::jsonb)
    ),
    'Should exclude groups from inactive communities even when include_inactive is enabled'
);

-- Should exclude inactive groups by default
select ok(
    not exists (
        select 1
        from search_groups_matches('{}'::jsonb)
        where group_id = :'groupInactiveID'
    ),
    'Should exclude inactive groups by default'
);

-- Should filter groups by bbox
select set_eq(
    $$
        select group_id
        from search_groups_matches('{
            "bbox_ne_lat": 38.0,
            "bbox_ne_lon": -122.0,
            "bbox_sw_lat": 37.0,
            "bbox_sw_lon": -123.0
        }'::jsonb)
    $$,
    array[:'groupSanFranciscoID']::uuid[],
    'Should filter groups by bbox'
);

-- Should filter groups by community
select set_eq(
    $$select group_id from search_groups_matches('{"community": ["sgm-community"]}'::jsonb)$$,
    array[:'groupAustinID', :'groupLondonID', :'groupNewYorkID', :'groupSanFranciscoID']::uuid[],
    'Should filter groups by community'
);

-- Should filter groups by distance
select set_eq(
    $$
        select group_id
        from search_groups_matches('{
            "community": ["sgm-community"],
            "distance": 1000,
            "latitude": 30.2672,
            "longitude": -97.7431
        }'::jsonb)
    $$,
    array[:'groupAustinID']::uuid[],
    'Should filter groups by distance'
);

-- Should filter groups by group category
select set_eq(
    $$
        select group_id
        from search_groups_matches('{
            "community": ["sgm-community"],
            "group_category": ["SGM-Business"]
        }'::jsonb)
    $$,
    array[:'groupLondonID']::uuid[],
    'Should filter groups by group category'
);

-- Should filter groups by region
select set_eq(
    $$
        select group_id
        from search_groups_matches('{
            "community": ["sgm-community"],
            "region": ["SGM-North-America"]
        }'::jsonb)
    $$,
    array[:'groupAustinID', :'groupNewYorkID', :'groupSanFranciscoID']::uuid[],
    'Should filter groups by region'
);

-- Should filter groups by text search query
select set_eq(
    $$
        select group_id
        from search_groups_matches('{
            "community": ["sgm-community"],
            "ts_query": "dock"
        }'::jsonb)
    $$,
    array[:'groupNewYorkID']::uuid[],
    'Should filter groups by text search query'
);

-- Should include inactive groups when include_inactive is enabled
select set_eq(
    $$
        select group_id
        from search_groups_matches('{
            "community": ["sgm-community"],
            "include_inactive": true
        }'::jsonb)
    $$,
    array[
        :'groupAustinID',
        :'groupInactiveID',
        :'groupLondonID',
        :'groupNewYorkID',
        :'groupSanFranciscoID'
    ]::uuid[],
    'Should include inactive groups when include_inactive is enabled'
);

-- Should leave distances empty unless sorting by distance
select ok(
    not exists (
        select 1
        from search_groups_matches('{
            "community": ["sgm-community"],
            "latitude": 37.7749,
            "longitude": -122.4194
        }'::jsonb)
        where distance is not null
    ),
    'Should leave distances empty unless sorting by distance'
);

-- Should match all communities when the community selection is empty
select set_eq(
    $$select group_id from search_groups_matches('{"community": []}'::jsonb)$$,
    array[
        :'groupAustinID',
        :'groupLondonID',
        :'groupNewYorkID',
        :'groupOtherID',
        :'groupSanFranciscoID'
    ]::uuid[],
    'Should match all communities when the community selection is empty'
);

-- Should match nothing for an unknown community
select is_empty(
    $$select group_id from search_groups_matches('{"community": ["sgm-unknown-community"]}'::jsonb)$$,
    'Should match nothing for an unknown community'
);

-- Should return every public group without filters
select set_eq(
    $$select group_id from search_groups_matches('{}'::jsonb)$$,
    array[
        :'groupAustinID',
        :'groupLondonID',
        :'groupNewYorkID',
        :'groupOtherID',
        :'groupSanFranciscoID'
    ]::uuid[],
    'Should return every public group without filters'
);

-- Should return the community, creation date, location and name of each match
select results_eq(
    $$
        select community_id, created_at, group_id, st_astext(location::geometry), name
        from search_groups_matches('{"community": ["sgm-other-community"]}'::jsonb)
    $$,
    format(
        $$
            values (
                %L::uuid,
                '2040-01-05 10:00:00+00'::timestamptz,
                %L::uuid,
                'POINT(-87.6298 41.8781)',
                'SGM Python Developers'
            )
        $$,
        :'communityOtherID',
        :'groupOtherID'
    ),
    'Should return the community, creation date, location and name of each match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
