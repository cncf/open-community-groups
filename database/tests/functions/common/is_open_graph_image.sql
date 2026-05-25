-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set deletedGroupID '00000000-0000-0000-0000-000000000024'
\set inactiveCommunityID '00000000-0000-0000-0000-000000000002'
\set inactiveCommunityCategoryID '00000000-0000-0000-0000-000000000012'
\set inactiveCommunityGroupID '00000000-0000-0000-0000-000000000025'
\set inactiveGroupID '00000000-0000-0000-0000-000000000023'
\set publicGroupID '00000000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    active,
    name,
    display_name,
    description,
    logo_url,
    og_image_url,
    banner_mobile_url,
    banner_url
) values
    (
        :'activeCommunityID',
        true,
        'active-community',
        'Active Community',
        'An active community.',
        'https://example.com/active-logo.png',
        '/images/community-og.png',
        'https://example.com/active-banner-mobile.png',
        'https://example.com/active-banner.png'
    ),
    (
        :'inactiveCommunityID',
        false,
        'inactive-community',
        'Inactive Community',
        'An inactive community.',
        'https://example.com/inactive-logo.png',
        '/images/inactive-community-og.png',
        'https://example.com/inactive-banner-mobile.png',
        'https://example.com/inactive-banner.png'
    );

-- Group categories
insert into group_category (group_category_id, name, community_id)
values
    (:'categoryID', 'Technology', :'activeCommunityID'),
    (:'inactiveCommunityCategoryID', 'Technology', :'inactiveCommunityID');

-- Groups
insert into "group" (
    group_id,
    active,
    deleted,
    name,
    slug,
    community_id,
    group_category_id,
    og_image_url
) values
    (
        :'publicGroupID',
        true,
        false,
        'Public Group',
        'public-group',
        :'activeCommunityID',
        :'categoryID',
        '/images/group-og.png'
    ),
    (
        :'inactiveGroupID',
        false,
        false,
        'Inactive Group',
        'inactive-group',
        :'activeCommunityID',
        :'categoryID',
        '/images/inactive-group-og.png'
    ),
    (
        :'deletedGroupID',
        false,
        true,
        'Deleted Group',
        'deleted-group',
        :'activeCommunityID',
        :'categoryID',
        '/images/deleted-group-og.png'
    ),
    (
        :'inactiveCommunityGroupID',
        true,
        false,
        'Inactive Community Group',
        'inactive-community-group',
        :'inactiveCommunityID',
        :'inactiveCommunityCategoryID',
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

select * from finish();
rollback;
