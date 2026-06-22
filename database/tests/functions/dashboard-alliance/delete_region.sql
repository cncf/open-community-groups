-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '2c0c0000-0000-0000-0000-000000000001'
\set groupCategoryID '2c0c0000-0000-0000-0000-000000000002'
\set groupID '2c0c0000-0000-0000-0000-000000000003'
\set inUseRegionID '2c0c0000-0000-0000-0000-000000000004'
\set unknownRegionID '2c0c0000-0000-0000-0000-000000000005'
\set unusedRegionID '2c0c0000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'cncf-seattle',
    'CNCF Seattle',
    'Alliance for region delete tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (
    group_category_id,
    alliance_id,
    name
) values (
    :'groupCategoryID',
    :'allianceID',
    'Platform'
);

-- Regions
insert into region (
    region_id,
    alliance_id,
    name
) values
    (:'inUseRegionID', :'allianceID', 'North America'),
    (:'unusedRegionID', :'allianceID', 'Europe');

-- Group using the first region
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    region_id
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Seattle Platform',
    'seattle-platform',
    :'inUseRegionID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block deleting region that is still referenced by groups
select throws_ok(
    format(
        $$ select delete_region(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'allianceID',
        :'inUseRegionID'
    ),
    'cannot delete region in use by groups',
    'Should block deleting region referenced by groups'
);

-- Should delete region with no group references
select lives_ok(
    format(
        $$ select delete_region(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'allianceID',
        :'unusedRegionID'
    ),
    'Should delete an unused region'
);
select results_eq(
    format(
        $$
    select count(*)::bigint
    from region r
    where r.region_id = %L::uuid
        $$,
        :'unusedRegionID'
    ),
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
    format(
        $$
        values (
            'region_deleted',
            null::uuid,
            null::text,
            %L::uuid,
            '{"name": "Europe"}'::jsonb,
            'region',
            %L::uuid
        )
        $$,
        :'allianceID',
        :'unusedRegionID'
    ),
    'Should create the expected audit row'
);

-- Should fail when target region does not exist
select throws_ok(
    format(
        $$ select delete_region(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'allianceID',
        :'unknownRegionID'
    ),
    'region not found',
    'Should fail when deleting a non-existing region'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
