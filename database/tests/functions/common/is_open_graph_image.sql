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
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url,

    active,
    og_image_url
) values
    (
        :'activeCommunityID',
        'active-community',
        'Active Community',
        'An active community.',
        'https://example.com/active-banner-mobile.png',
        'https://example.com/active-banner.png',
        'https://example.com/active-logo.png',

        true,
        '/images/community-og.png'
    ),
    (
        :'inactiveCommunityID',
        'inactive-community',
        'Inactive Community',
        'An inactive community.',
        'https://example.com/inactive-banner-mobile.png',
        'https://example.com/inactive-banner.png',
        'https://example.com/inactive-logo.png',

        false,
        '/images/inactive-community-og.png'
    );

-- Group categories
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategoryID', :'activeCommunityID', 'Technology'),
    (:'inactiveCommunityCategoryID', :'inactiveCommunityID', 'Technology');

-- Groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,

    active,
    deleted,
    og_image_url
) values
    (
        :'publicGroupID',
        :'activeCommunityID',
        :'groupCategoryID',
        'Public Group',
        'public-group',

        true,
        false,
        '/images/group-og.png'
    ),
    (
        :'inactiveGroupID',
        :'activeCommunityID',
        :'groupCategoryID',
        'Inactive Group',
        'inactive-group',

        false,
        false,
        '/images/inactive-group-og.png'
    ),
    (
        :'deletedGroupID',
        :'activeCommunityID',
        :'groupCategoryID',
        'Deleted Group',
        'deleted-group',

        false,
        true,
        '/images/deleted-group-og.png'
    ),
    (
        :'inactiveCommunityGroupID',
        :'inactiveCommunityID',
        :'inactiveCommunityCategoryID',
        'Inactive Community Group',
        'inactive-community-group',

        true,
        false,
        '/images/inactive-community-group-og.png'
    );

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
