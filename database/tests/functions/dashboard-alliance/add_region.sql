-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '00000000-0000-0000-0000-000000000001'

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
    'Alliance for region tests',
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
        null::uuid,
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
    where r.alliance_id = '00000000-0000-0000-0000-000000000001'::uuid
    $$,
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
            alliance_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    $$
        select
            'region_added',
            null::uuid,
            null::text,
            '00000000-0000-0000-0000-000000000001'::uuid,
            'region',
            region_id
        from region
        where alliance_id = '00000000-0000-0000-0000-000000000001'::uuid
    $$,
    'Should create the expected audit row'
);

-- Should not allow duplicate region normalized name in same alliance
select throws_ok(
    $$ select add_region(
        null::uuid,
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
