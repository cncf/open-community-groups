-- Tests searching the minimal groups projection for the explore map.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityCappedID '5eaa0000-0000-0000-0000-000000000001'
\set communityHundredID '5eaa0000-0000-0000-0000-000000000002'
\set communityID '5eaa0000-0000-0000-0000-000000000003'
\set groupAlphaID '5eaa0000-0000-0000-0000-000000000004'
\set groupCategoryCappedID '5eaa0000-0000-0000-0000-000000000005'
\set groupCategoryHundredID '5eaa0000-0000-0000-0000-000000000006'
\set groupCategoryID '5eaa0000-0000-0000-0000-000000000007'
\set groupTieHighID '5eaa0000-0000-0000-0000-000000000009'
\set groupTieLowID '5eaa0000-0000-0000-0000-000000000008'
\set groupUnlocatedID '5eaa0000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community with more located groups than the limit
select fx_community(:'communityCappedID', jsonb_build_object('name', 'sgc-capped-community'));

-- Community with just over a hundred located groups
select fx_community(:'communityHundredID', jsonb_build_object('name', 'sgc-hundred-community'));

-- Community with groups covering fields, ordering and location eligibility
select fx_community(:'communityID', jsonb_build_object('name', 'sgc-community'));

-- Group category in the capped community
select fx_group_category(:'groupCategoryCappedID', :'communityCappedID');

-- Group category in the hundred community
select fx_group_category(:'groupCategoryHundredID', :'communityHundredID');

-- Group category in the main community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group located in Madrid with a pretty slug
select fx_group(:'groupAlphaID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-3.7038 40.4168)'),
    'name', 'SGC Alpha',
    'slug', 'sgc-alpha',
    'slug_pretty', 'sgc-alpha-pretty'
));

-- Tied group in Lisbon with the higher group ID, inserted first
select fx_group(:'groupTieHighID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-9.1393 38.7223)'),
    'name', 'SGC Tied Group',
    'slug', 'sgc-tie-high'
));

-- Tied group in Lisbon with the lower group ID, sharing the name
select fx_group(:'groupTieLowID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-9.1393 38.7223)'),
    'name', 'SGC Tied Group',
    'slug', 'sgc-tie-low'
));

-- Group without a location
select fx_group(:'groupUnlocatedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'name', 'SGC Beta',
    'slug', 'sgc-unlocated'
));

-- One more located group than the limit, the last one by name stretching the extent
insert into "group" (
    group_id,
    active,
    community_id,
    group_category_id,
    name,
    slug,
    location
)
select
    format('5eaa0000-0000-0000-0002-%s', lpad(i::text, 12, '0'))::uuid,
    true,
    :'communityCappedID',
    :'groupCategoryCappedID',
    'SGC Capped Group ' || lpad(i::text, 4, '0'),
    'sgc-capped-group-' || i,
    case
        when i = 1001 then ST_GeogFromText('POINT(20 60)')
        else ST_SetSRID(ST_MakePoint((i % 100) * 0.01, 40 + (i / 100) * 0.01), 4326)::geography
    end
from generate_series(1, 1001) i;

-- Just over a hundred located groups
insert into "group" (
    group_id,
    active,
    community_id,
    group_category_id,
    name,
    slug,
    location
)
select
    format('5eaa0000-0000-0000-0001-%s', lpad(i::text, 12, '0'))::uuid,
    true,
    :'communityHundredID',
    :'groupCategoryHundredID',
    'SGC Hundred Group ' || lpad(i::text, 3, '0'),
    'sgc-hundred-group-' || i,
    ST_SetSRID(ST_MakePoint(-6 + i * 0.01, 43), 4326)::geography
from generate_series(1, 101) i;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should bound every match beyond the limit
select is(
    search_groups_minimal('{"community": ["sgc-capped-community"]}'::jsonb, 1000)::jsonb->'bbox',
    '{"ne_lat": 60, "ne_lon": 20, "sw_lat": 40, "sw_lon": 0}'::jsonb,
    'Should bound every match beyond the limit'
);

-- Should cap the groups at the limit and flag the result as truncated
select is(
    (
        select jsonb_build_object(
            'items', jsonb_array_length(result->'groups'),
            'last_group_id', result->'groups'->999->>'group_id',
            'total', result->'total',
            'truncated', result->'truncated'
        )
        from (
            select search_groups_minimal(
                '{"community": ["sgc-capped-community"]}'::jsonb,
                1000
            )::jsonb as result
        ) as output
    ),
    jsonb_build_object(
        'items', 1000,
        'last_group_id', '5eaa0000-0000-0000-0002-000000001000',
        'total', 1001,
        'truncated', true
    ),
    'Should cap the groups at the limit and flag the result as truncated'
);

-- Should include only groups with a location
select is(
    (search_groups_minimal('{"community": ["sgc-community"]}'::jsonb, 1000)::jsonb->>'total')::int,
    3,
    'Should include only groups with a location'
);

-- Should order groups by name then group ID
select is(
    (
        select jsonb_agg(group_item->>'group_id' order by position)
        from jsonb_array_elements(
            search_groups_minimal('{"community": ["sgc-community"]}'::jsonb, 1000)::jsonb->'groups'
        ) with ordinality as groups(group_item, position)
    ),
    jsonb_build_array(:'groupAlphaID', :'groupTieLowID', :'groupTieHighID'),
    'Should order groups by name then group ID'
);

-- Should return an empty result when nothing matches
select is(
    search_groups_minimal('{
        "bbox_ne_lat": -39.0,
        "bbox_ne_lon": -29.0,
        "bbox_sw_lat": -40.0,
        "bbox_sw_lon": -30.0,
        "community": ["sgc-community"]
    }'::jsonb, 1000)::jsonb,
    '{"groups": [], "total": 0, "bbox": null, "truncated": false}'::jsonb,
    'Should return an empty result when nothing matches'
);

-- Should return every match up to the limit
select is(
    (
        select jsonb_build_object(
            'items', jsonb_array_length(result->'groups'),
            'total', result->'total',
            'truncated', result->'truncated'
        )
        from (
            select search_groups_minimal(
                '{"community": ["sgc-hundred-community"]}'::jsonb,
                1000
            )::jsonb as result
        ) as output
    ),
    jsonb_build_object(
        'items', 101,
        'total', 101,
        'truncated', false
    ),
    'Should return every match up to the limit'
);

-- Should return the required and optional fields of each group
select is(
    search_groups_minimal('{
        "bbox_ne_lat": 41.0,
        "bbox_ne_lon": -3.0,
        "bbox_sw_lat": 40.0,
        "bbox_sw_lon": -4.0,
        "community": ["sgc-community"]
    }'::jsonb, 1000)::jsonb->'groups',
    jsonb_build_array(
        jsonb_build_object(
            'active', true,
            'community_name', 'sgc-community',
            'group_id', :'groupAlphaID',
            'name', 'SGC Alpha',
            'slug', 'sgc-alpha',

            'latitude', 40.4168,
            'longitude', -3.7038,
            'slug_pretty', 'sgc-alpha-pretty'
        )
    ),
    'Should return the required and optional fields of each group'
);

-- Should strip absent optional fields
select is(
    search_groups_minimal('{
        "bbox_ne_lat": 39.0,
        "bbox_ne_lon": -9.0,
        "bbox_sw_lat": 38.0,
        "bbox_sw_lon": -10.0,
        "community": ["sgc-community"]
    }'::jsonb, 1000)::jsonb->'groups'->0,
    jsonb_build_object(
        'active', true,
        'community_name', 'sgc-community',
        'group_id', :'groupTieLowID',
        'name', 'SGC Tied Group',
        'slug', 'sgc-tie-low',

        'latitude', 38.7223,
        'longitude', -9.1393
    ),
    'Should strip absent optional fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
