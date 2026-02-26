-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000011'
\set inUseRegionID '00000000-0000-0000-0000-000000000012'
\set unusedRegionID '00000000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'cncf-seattle',
    'CNCF Seattle',
    'Community for region delete tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group category
insert into group_category (
    community_id,
    group_category_id,
    name
) values (
    :'communityID',
    :'groupCategoryID',
    'Platform'
);

-- Regions
insert into region (
    community_id,
    region_id,
    name
) values
    (:'communityID', :'inUseRegionID', 'North America'),
    (:'communityID', :'unusedRegionID', 'Europe');

-- Group using the first region
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    region_id,
    slug
) values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'Seattle Platform',
    :'inUseRegionID',
    'seattle-platform'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block deleting region that is still referenced by groups
select throws_ok(
    $$ select delete_region(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000012'::uuid
    ) $$,
    'cannot delete region in use by groups',
    'Should block deleting region referenced by groups'
);

-- Should delete region with no group references
select lives_ok(
    $$ select delete_region(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000013'::uuid
    ) $$,
    'Should delete an unused region'
);
select results_eq(
    $$
    select count(*)::bigint
    from region r
    where r.region_id = '00000000-0000-0000-0000-000000000013'::uuid
    $$,
    $$ values (0::bigint) $$,
    'Unused region should be deleted'
);

-- Should fail when target region does not exist
select throws_ok(
    $$ select delete_region(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000099'::uuid
    ) $$,
    'region not found',
    'Should fail when deleting a non-existing region'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
