-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

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
    'Community for event category tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create a new event category and auto-generate slug
select lives_ok(
    $$ select add_event_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_object('name', 'Cloud Native Meetup')
    ) $$,
    'Should create an event category with generated slug'
);
select results_eq(
    $$
    select
        ec.name,
        ec.slug
    from event_category ec
    where ec.community_id = '00000000-0000-0000-0000-000000000001'::uuid
    $$,
    $$ values ('Cloud Native Meetup'::text, 'cloud-native-meetup'::text) $$,
    'Should store category name and generated slug'
);

-- Should not allow duplicate event category slug in same community
select throws_ok(
    $$ select add_event_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_object('name', 'cloud native meetup')
    ) $$,
    'event category already exists',
    'Should reject duplicate event category names'
);

-- Should reject names that generate an empty slug
select throws_ok(
    $$ select add_event_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_object('name', '!!!')
    ) $$,
    'event category name is invalid',
    'Should reject event category names that generate empty slugs'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
