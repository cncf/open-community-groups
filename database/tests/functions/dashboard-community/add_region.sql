-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c060000-0000-0000-0000-000000000001'

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
    'Community for region tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create a new region and auto-generate normalized name
select lives_ok(
    format(
        $$ select add_region(
        null::uuid,
        %L::uuid,
        jsonb_build_object('name', 'North America')
    ) $$,
        :'communityID'
    ),
    'Should create a region with generated normalized name'
);
select results_eq(
    format(
        $$
    select
        r.name,
        r.normalized_name
    from region r
    where r.community_id = %L::uuid
        $$,
        :'communityID'
    ),
    $$ values ('North America'::text, 'north-america'::text) $$,
    'Should store region name and generated normalized name'
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
        select
            'region_added',
            null::uuid,
            null::text,
            %L::uuid,
            'region',
            region_id
        from region
        where community_id = %L::uuid
        $$,
        :'communityID',
        :'communityID'
    ),
    'Should create the expected audit row'
);

-- Should not allow duplicate region normalized name in same community
select throws_ok(
    format(
        $$ select add_region(
        null::uuid,
        %L::uuid,
        jsonb_build_object('name', 'north america')
    ) $$,
        :'communityID'
    ),
    'region already exists',
    'Should reject duplicate region names'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
