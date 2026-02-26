-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set inUseCategoryID '00000000-0000-0000-0000-000000000011'
\set unusedCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000013'

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
    'Community for group category delete tests',
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
    (:'communityID', :'inUseCategoryID', 'Platform'),
    (:'communityID', :'unusedCategoryID', 'Security');

-- Group using the first category
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    :'inUseCategoryID',
    :'groupID',
    'Seattle Platform',
    'seattle-platform'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block deleting category that is still referenced by groups
select throws_ok(
    $$ select delete_group_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000011'::uuid
    ) $$,
    'cannot delete group category in use by groups',
    'Should block deleting group category referenced by groups'
);

-- Should delete category with no group references
select lives_ok(
    $$ select delete_group_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000012'::uuid
    ) $$,
    'Should delete an unused group category'
);
select results_eq(
    $$
    select count(*)::bigint
    from group_category gc
    where gc.group_category_id = '00000000-0000-0000-0000-000000000012'::uuid
    $$,
    $$ values (0::bigint) $$,
    'Unused group category should be deleted'
);

-- Should fail when target category does not exist
select throws_ok(
    $$ select delete_group_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000099'::uuid
    ) $$,
    'group category not found',
    'Should fail when deleting a non-existing group category'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
