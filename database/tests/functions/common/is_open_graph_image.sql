-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeAllianceID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set deletedGroupID '00000000-0000-0000-0000-000000000024'
\set inactiveAllianceID '00000000-0000-0000-0000-000000000002'
\set inactiveAllianceCategoryID '00000000-0000-0000-0000-000000000012'
\set inactiveAllianceGroupID '00000000-0000-0000-0000-000000000025'
\set inactiveGroupID '00000000-0000-0000-0000-000000000023'
\set publicGroupID '00000000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
insert into alliance (
    alliance_id,
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
        :'activeAllianceID',
        true,
        'active-alliance',
        'Active Alliance',
        'An active alliance.',
        'https://example.com/active-logo.png',
        '/images/alliance-og.png',
        'https://example.com/active-banner-mobile.png',
        'https://example.com/active-banner.png'
    ),
    (
        :'inactiveAllianceID',
        false,
        'inactive-alliance',
        'Inactive Alliance',
        'An inactive alliance.',
        'https://example.com/inactive-logo.png',
        '/images/inactive-alliance-og.png',
        'https://example.com/inactive-banner-mobile.png',
        'https://example.com/inactive-banner.png'
    );

-- Group categories
insert into group_category (group_category_id, name, alliance_id)
values
    (:'categoryID', 'Technology', :'activeAllianceID'),
    (:'inactiveAllianceCategoryID', 'Technology', :'inactiveAllianceID');

-- Groups
insert into "group" (
    group_id,
    active,
    deleted,
    name,
    slug,
    alliance_id,
    group_category_id,
    og_image_url
) values
    (
        :'publicGroupID',
        true,
        false,
        'Public Group',
        'public-group',
        :'activeAllianceID',
        :'categoryID',
        '/images/group-og.png'
    ),
    (
        :'inactiveGroupID',
        false,
        false,
        'Inactive Group',
        'inactive-group',
        :'activeAllianceID',
        :'categoryID',
        '/images/inactive-group-og.png'
    ),
    (
        :'deletedGroupID',
        false,
        true,
        'Deleted Group',
        'deleted-group',
        :'activeAllianceID',
        :'categoryID',
        '/images/deleted-group-og.png'
    ),
    (
        :'inactiveAllianceGroupID',
        true,
        false,
        'Inactive Alliance Group',
        'inactive-alliance-group',
        :'inactiveAllianceID',
        :'inactiveAllianceCategoryID',
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

select * from finish();
rollback;
