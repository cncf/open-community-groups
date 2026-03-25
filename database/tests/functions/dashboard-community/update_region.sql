-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set region1ID '00000000-0000-0000-0000-000000000011'
\set region2ID '00000000-0000-0000-0000-000000000012'

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
    'Community for region update tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Regions
insert into region (
    community_id,
    region_id,
    name
) values
    (:'communityID', :'region1ID', 'North America'),
    (:'communityID', :'region2ID', 'Europe');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update region name and generated normalized name
select lives_ok(
    $$ select update_region(
        null::uuid,
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000011'::uuid,
        jsonb_build_object('name', 'Latin America')
    ) $$,
    'Should update region name'
);
select results_eq(
    $$
    select
        r.name,
        r.normalized_name
    from region r
    where r.region_id = '00000000-0000-0000-0000-000000000011'::uuid
    $$,
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
    $$
        values (
            'region_updated',
            null::uuid,
            null::text,
            '00000000-0000-0000-0000-000000000001'::uuid,
            'region',
            '00000000-0000-0000-0000-000000000011'::uuid
        )
    $$,
    'Should create the expected audit row'
);

-- Should reject duplicate normalized names in same community
select throws_ok(
    $$ select update_region(
        null::uuid,
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000011'::uuid,
        jsonb_build_object('name', 'Europe')
    ) $$,
    'region already exists',
    'Should reject duplicate region names'
);

-- Should fail when target region does not exist
select throws_ok(
    $$ select update_region(
        null::uuid,
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000099'::uuid,
        jsonb_build_object('name', 'APAC')
    ) $$,
    'region not found',
    'Should fail when updating a non-existing region'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
