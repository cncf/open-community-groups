-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

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
    'Community for group category update tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group categories
insert into group_category (
    community_id,
    group_category_id,
    name
) values
    (:'communityID', :'category1ID', 'Meetup'),
    (:'communityID', :'category2ID', 'Conference');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update category name and generated normalized name
select lives_ok(
    $$ select update_group_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000011'::uuid,
        jsonb_build_object('name', 'Lightning Talks')
    ) $$,
    'Should update group category name'
);
select results_eq(
    $$
    select
        gc.name,
        gc.normalized_name
    from group_category gc
    where gc.group_category_id = '00000000-0000-0000-0000-000000000011'::uuid
    $$,
    $$ values ('Lightning Talks'::text, 'lightning-talks'::text) $$,
    'Should persist updated group category values'
);

-- Should reject duplicate normalized names in same community
select throws_ok(
    $$ select update_group_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000011'::uuid,
        jsonb_build_object('name', 'Conference')
    ) $$,
    'group category already exists',
    'Should reject duplicate group category names'
);

-- Should fail when target category does not exist
select throws_ok(
    $$ select update_group_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000099'::uuid,
        jsonb_build_object('name', 'Workshops')
    ) $$,
    'group category not found',
    'Should fail when updating a non-existing group category'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
