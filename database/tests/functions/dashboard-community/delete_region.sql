-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c0c0000-0000-0000-0000-000000000001'
\set groupCategoryID '2c0c0000-0000-0000-0000-000000000002'
\set groupID '2c0c0000-0000-0000-0000-000000000003'
\set inUseRegionID '2c0c0000-0000-0000-0000-000000000004'
\set unknownRegionID '2c0c0000-0000-0000-0000-000000000005'
\set unusedRegionID '2c0c0000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'cncf-seattle',
    'CNCF Seattle',
    'Community for region delete tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'groupCategoryID',
    :'communityID',
    'Platform'
);

-- Regions
insert into region (
    region_id,
    community_id,
    name
) values
    (:'inUseRegionID', :'communityID', 'North America'),
    (:'unusedRegionID', :'communityID', 'Europe');

-- Group using the first region
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    region_id
) values (
    :'groupID',
    :'communityID',
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
        :'communityID',
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
        :'communityID',
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
            community_id,
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
        :'communityID',
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
        :'communityID',
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
