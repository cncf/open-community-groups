-- Tests projecting group regions as the shared group JSON shape.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c4a20000-0000-0000-0000-000000000001'
\set groupCategoryID 'c4a20000-0000-0000-0000-000000000002'
\set groupNoRegionID 'c4a20000-0000-0000-0000-000000000003'
\set regionID 'c4a20000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the group and region
select fx_community(:'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Region with a display order
insert into region (region_id, community_id, name, "order")
values (:'regionID', :'communityID', 'North America', 2);

-- Group without a region
select fx_group(:'groupNoRegionID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'region_id', null
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should project the region fields
select is(
    (
        select group_region_json(r)::jsonb
        from region r
        where r.region_id = :'regionID'::uuid
    ),
    jsonb_build_object(
        'region_id', :'regionID'::uuid,
        'name', 'North America',
        'normalized_name', 'north-america',
        'order', 2
    ),
    'Should project the region fields'
);

-- Should return null for a group without a region
select is(
    (
        select count(*)
        from "group" g
        left join region r using (region_id)
        where g.group_id = :'groupNoRegionID'::uuid
        and group_region_json(r) is null
    ),
    1::bigint,
    'Should return null for a group without a region'
);

-- Should return null for a null region
select is(
    group_region_json(null::region)::text,
    null,
    'Should return null for a null region'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
