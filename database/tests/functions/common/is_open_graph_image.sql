-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeAllianceID '0c0d0000-0000-0000-0000-000000000001'
\set deletedGroupID '0c0d0000-0000-0000-0000-000000000002'
\set groupCategoryID '0c0d0000-0000-0000-0000-000000000003'
\set inactiveAllianceCategoryID '0c0d0000-0000-0000-0000-000000000004'
\set inactiveAllianceGroupID '0c0d0000-0000-0000-0000-000000000005'
\set inactiveAllianceID '0c0d0000-0000-0000-0000-000000000006'
\set inactiveGroupID '0c0d0000-0000-0000-0000-000000000007'
\set publicGroupID '0c0d0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
insert into alliance (
    alliance_id,
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
        :'activeAllianceID',
        'active-alliance',
        'Active Alliance',
        'An active alliance.',
        'https://example.com/active-banner-mobile.png',
        'https://example.com/active-banner.png',
        'https://example.com/active-logo.png',

        true,
        '/images/alliance-og.png'
    ),
    (
        :'inactiveAllianceID',
        'inactive-alliance',
        'Inactive Alliance',
        'An inactive alliance.',
        'https://example.com/inactive-banner-mobile.png',
        'https://example.com/inactive-banner.png',
        'https://example.com/inactive-logo.png',

        false,
        '/images/inactive-alliance-og.png'
    );

-- Group categories
insert into group_category (group_category_id, alliance_id, name)
values
    (:'groupCategoryID', :'activeAllianceID', 'Technology'),
    (:'inactiveAllianceCategoryID', :'inactiveAllianceID', 'Technology');

-- Groups
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,

    active,
    deleted,
    og_image_url
) values
    (
        :'publicGroupID',
        :'activeAllianceID',
        :'groupCategoryID',
        'Public Group',
        'public-group',

        true,
        false,
        '/images/group-og.png'
    ),
    (
        :'inactiveGroupID',
        :'activeAllianceID',
        :'groupCategoryID',
        'Inactive Group',
        'inactive-group',

        false,
        false,
        '/images/inactive-group-og.png'
    ),
    (
        :'deletedGroupID',
        :'activeAllianceID',
        :'groupCategoryID',
        'Deleted Group',
        'deleted-group',

        false,
        true,
        '/images/deleted-group-og.png'
    ),
    (
        :'inactiveAllianceGroupID',
        :'inactiveAllianceID',
        :'inactiveAllianceCategoryID',
        'Inactive Alliance Group',
        'inactive-alliance-group',

        true,
        false,
        '/images/inactive-alliance-group-og.png'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return true for active alliance Open Graph images
select is(
    is_open_graph_image('/images/alliance-og.png'),
    true,
    'Returns true for active alliance Open Graph images'
);

-- Should return false for inactive alliance Open Graph images
select is(
    is_open_graph_image('/images/inactive-alliance-og.png'),
    false,
    'Returns false for inactive alliance Open Graph images'
);

-- Should return true for active group Open Graph images from active alliances
select is(
    is_open_graph_image('/images/group-og.png'),
    true,
    'Returns true for active group Open Graph images from active alliances'
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

-- Should return false for group Open Graph images from inactive alliances
select is(
    is_open_graph_image('/images/inactive-alliance-group-og.png'),
    false,
    'Returns false for group Open Graph images from inactive alliances'
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
