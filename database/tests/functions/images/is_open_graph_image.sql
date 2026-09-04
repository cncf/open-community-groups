-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '0c0d0000-0000-0000-0000-000000000001'
\set deletedGroupID '0c0d0000-0000-0000-0000-000000000002'
\set groupCategoryID '0c0d0000-0000-0000-0000-000000000003'
\set inactiveCommunityCategoryID '0c0d0000-0000-0000-0000-000000000004'
\set inactiveCommunityGroupID '0c0d0000-0000-0000-0000-000000000005'
\set inactiveCommunityID '0c0d0000-0000-0000-0000-000000000006'
\set inactiveGroupID '0c0d0000-0000-0000-0000-000000000007'
\set publicGroupID '0c0d0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
select fx_community(:'activeCommunityID', jsonb_build_object(
    'name', 'active-community',
    'og_image_url', '/images/community-og.png'
));
select fx_community(:'inactiveCommunityID', jsonb_build_object(
    'active', false,
    'name', 'inactive-community',
    'og_image_url', '/images/inactive-community-og.png'
));

-- Baseline group categories
select fx_group_category(:'groupCategoryID', :'activeCommunityID');
select fx_group_category(:'inactiveCommunityCategoryID', :'inactiveCommunityID');

-- Groups
select fx_group(:'publicGroupID', :'activeCommunityID', :'groupCategoryID', jsonb_build_object('og_image_url', '/images/group-og.png'));
select fx_group(:'inactiveGroupID', :'activeCommunityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'og_image_url', '/images/inactive-group-og.png',
    'slug', 'inactive-group'
));
select fx_group(:'deletedGroupID', :'activeCommunityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'og_image_url', '/images/deleted-group-og.png',
    'slug', 'deleted-group'
));
select fx_group(:'inactiveCommunityGroupID', :'inactiveCommunityID', :'inactiveCommunityCategoryID', jsonb_build_object(
    'og_image_url', '/images/inactive-community-group-og.png',
    'slug', 'inactive-community-group'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return true for active community Open Graph images
select is(
    is_open_graph_image('/images/community-og.png'),
    true,
    'Returns true for active community Open Graph images'
);

-- Should return false for inactive community Open Graph images
select is(
    is_open_graph_image('/images/inactive-community-og.png'),
    false,
    'Returns false for inactive community Open Graph images'
);

-- Should return true for active group Open Graph images from active communities
select is(
    is_open_graph_image('/images/group-og.png'),
    true,
    'Returns true for active group Open Graph images from active communities'
);

-- Should return false for inactive group Open Graph images
select is(
    is_open_graph_image('/images/inactive-group-og.png'),
    false,
    'Returns false for inactive group Open Graph images'
);

-- Should return false for deleted group Open Graph images
select is(
    is_open_graph_image('/images/deleted-group-og.png'),
    false,
    'Returns false for deleted group Open Graph images'
);

-- Should return false for group Open Graph images from inactive communities
select is(
    is_open_graph_image('/images/inactive-community-group-og.png'),
    false,
    'Returns false for group Open Graph images from inactive communities'
);

-- Should return false for unreferenced images
select is(
    is_open_graph_image('/images/missing-og.png'),
    false,
    'Returns false for unreferenced images'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
