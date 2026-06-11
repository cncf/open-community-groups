-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c180000-0000-0000-0000-000000000001'
\set region1ID '2c180000-0000-0000-0000-000000000002'
\set region2ID '2c180000-0000-0000-0000-000000000003'
\set unknownRegionID '2c180000-0000-0000-0000-000000000004'

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
    'Community for region update tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Regions
insert into region (
    region_id,
    community_id,
    name
) values
    (:'region1ID', :'communityID', 'North America'),
    (:'region2ID', :'communityID', 'Europe');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update region name and generated normalized name
select lives_ok(
    format(
        $$ select update_region(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Latin America')
    ) $$,
        :'communityID',
        :'region1ID'
    ),
    'Should update region name'
);
select results_eq(
    format(
        $$
    select
        r.name,
        r.normalized_name
    from region r
    where r.region_id = %L::uuid
        $$,
        :'region1ID'
    ),
    $$ values ('Latin America'::text, 'latin-america'::text) $$,
    'Should persist updated region values'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'region_updated',
            null::uuid,
            null::text,
            %L::uuid,
            'region',
            %L::uuid
        )
        $$,
        :'communityID',
        :'region1ID'
    ),
    'Should create the expected audit row'
);

-- Should reject duplicate normalized names in same community
select throws_ok(
    format(
        $$ select update_region(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Europe')
    ) $$,
        :'communityID',
        :'region1ID'
    ),
    'region already exists',
    'Should reject duplicate region names'
);

-- Should fail when target region does not exist
select throws_ok(
    format(
        $$ select update_region(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'APAC')
    ) $$,
        :'communityID',
        :'unknownRegionID'
    ),
    'region not found',
    'Should fail when updating a non-existing region'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
