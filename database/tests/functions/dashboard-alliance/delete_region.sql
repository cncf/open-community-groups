-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '00000000-0000-0000-0000-000000000001'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000011'
\set inUseRegionID '00000000-0000-0000-0000-000000000012'
\set unusedRegionID '00000000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'allianceID',
    'goup-seattle',
    'Goup Seattle',
    'Alliance for region delete tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group category
insert into group_category (
    alliance_id,
    group_category_id,
    name
) values (
    :'allianceID',
    :'groupCategoryID',
    'Platform'
);

-- Regions
insert into region (
    alliance_id,
    region_id,
    name
) values
    (:'allianceID', :'inUseRegionID', 'North America'),
    (:'allianceID', :'unusedRegionID', 'Europe');

-- Group using the first region
insert into "group" (
    alliance_id,
    group_category_id,
    group_id,
    name,
    region_id,
    slug
) values (
    :'allianceID',
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
        null::uuid,
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000012'::uuid
    ) $$,
    'cannot delete region in use by groups',
    'Should block deleting region referenced by groups'
);

-- Should delete region with no group references
select lives_ok(
    $$ select delete_region(
        null::uuid,
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

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            alliance_id,
            details,
            resource_type,
            resource_id
        from audit_log
    $$,
    $$
        values (
            'region_deleted',
            null::uuid,
            null::text,
            '00000000-0000-0000-0000-000000000001'::uuid,
            '{"name": "Europe"}'::jsonb,
            'region',
            '00000000-0000-0000-0000-000000000013'::uuid
        )
    $$,
    'Should create the expected audit row'
);

-- Should fail when target region does not exist
select throws_ok(
    $$ select delete_region(
        null::uuid,
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
