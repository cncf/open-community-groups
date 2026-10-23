-- Tests projecting group categories as the shared group JSON shape.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c4a10000-0000-0000-0000-000000000001'
\set groupCategoryID 'c4a10000-0000-0000-0000-000000000002'
\set groupCategoryUnorderedID 'c4a10000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the categories
select fx_community(:'communityID');

-- Category with a display order
insert into group_category (group_category_id, community_id, name, "order")
values (:'groupCategoryID', :'communityID', 'Cloud Native', 3);

-- Category without a display order
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryUnorderedID', :'communityID', 'Open Source');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep a null order in the projection
select is(
    (
        select group_category_json(gc)::jsonb
        from group_category gc
        where gc.group_category_id = :'groupCategoryUnorderedID'::uuid
    ),
    jsonb_build_object(
        'group_category_id', :'groupCategoryUnorderedID'::uuid,
        'name', 'Open Source',
        'normalized_name', 'open-source',
        'order', null
    ),
    'Should keep a null order in the projection'
);

-- Should project the category fields
select is(
    (
        select group_category_json(gc)::jsonb
        from group_category gc
        where gc.group_category_id = :'groupCategoryID'::uuid
    ),
    jsonb_build_object(
        'group_category_id', :'groupCategoryID'::uuid,
        'name', 'Cloud Native',
        'normalized_name', 'cloud-native',
        'order', 3
    ),
    'Should project the category fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
