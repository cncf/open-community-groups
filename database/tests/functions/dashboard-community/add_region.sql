-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'

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
    'Community for region tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create a new region and auto-generate normalized name
select lives_ok(
    $$ select add_region(
        '00000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_object('name', 'North America')
    ) $$,
    'Should create a region with generated normalized name'
);
select results_eq(
    $$
    select
        r.name,
        r.normalized_name
    from region r
    where r.community_id = '00000000-0000-0000-0000-000000000001'::uuid
    $$,
    $$ values ('North America'::text, 'north-america'::text) $$,
    'Should store region name and generated normalized name'
);

-- Should not allow duplicate region normalized name in same community
select throws_ok(
    $$ select add_region(
        '00000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_object('name', 'north america')
    ) $$,
    'region already exists',
    'Should reject duplicate region names'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
