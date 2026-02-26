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
    'Community for group category tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create a new group category and auto-generate normalized name
select lives_ok(
    $$ select add_group_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_object('name', 'Platform Engineering')
    ) $$,
    'Should create a group category with generated normalized name'
);
select results_eq(
    $$
    select
        gc.name,
        gc.normalized_name
    from group_category gc
    where gc.community_id = '00000000-0000-0000-0000-000000000001'::uuid
    $$,
    $$ values ('Platform Engineering'::text, 'platform-engineering'::text) $$,
    'Should store category name and generated normalized name'
);

-- Should not allow duplicate group category normalized name in same community
select throws_ok(
    $$ select add_group_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_object('name', 'platform engineering')
    ) $$,
    'group category already exists',
    'Should reject duplicate group category names'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
