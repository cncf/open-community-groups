-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'

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
    'Community for event category update tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Event categories
insert into event_category (
    community_id,
    event_category_id,
    name
) values
    (:'communityID', :'category1ID', 'Meetup'),
    (:'communityID', :'category2ID', 'Conference');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update category name and regenerate slug
select lives_ok(
    $$ select update_event_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000011'::uuid,
        jsonb_build_object('name', 'Lightning Talks')
    ) $$,
    'Should update event category and regenerate slug'
);
select results_eq(
    $$
    select
        ec.name,
        ec.slug
    from event_category ec
    where ec.event_category_id = '00000000-0000-0000-0000-000000000011'::uuid
    $$,
    $$ values ('Lightning Talks'::text, 'lightning-talks'::text) $$,
    'Should persist updated event category values'
);

-- Should reject duplicated slug in same community
select throws_ok(
    $$ select update_event_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000011'::uuid,
        jsonb_build_object('name', 'Conference')
    ) $$,
    'event category already exists',
    'Should reject duplicate event category names'
);

-- Should reject names that generate an empty slug
select throws_ok(
    $$ select update_event_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000011'::uuid,
        jsonb_build_object('name', '!!!')
    ) $$,
    'event category name is invalid',
    'Should reject event category names that generate empty slugs'
);

-- Should fail when target category does not exist
select throws_ok(
    $$ select update_event_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000099'::uuid,
        jsonb_build_object('name', 'Workshops')
    ) $$,
    'event category not found',
    'Should fail when updating a non-existing event category'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
