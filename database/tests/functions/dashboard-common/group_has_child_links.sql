-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeChildID '1c090000-0000-0000-0000-000000000001'
\set activeParentID '1c090000-0000-0000-0000-000000000002'
\set communityID '1c090000-0000-0000-0000-000000000003'
\set deletedChildID '1c090000-0000-0000-0000-000000000004'
\set deletedOnlyParentID '1c090000-0000-0000-0000-000000000005'
\set groupCategoryID '1c090000-0000-0000-0000-000000000006'
\set inactiveChildID '1c090000-0000-0000-0000-000000000007'
\set inactiveOnlyParentID '1c090000-0000-0000-0000-000000000008'
\set otherCommunityChildID '1c090000-0000-0000-0000-000000000009'
\set otherCommunityGroupCategoryID '1c090000-0000-0000-0000-00000000000a'
\set otherCommunityID '1c090000-0000-0000-0000-00000000000b'
\set otherCommunityParentID '1c090000-0000-0000-0000-00000000000c'
\set unrelatedGroupID '1c090000-0000-0000-0000-00000000000d'

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
    logo_url
) values
    (
        :'communityID',
        'child-links-community',
        'Child Links Community',
        'Community for child link tests',
        'https://example.com/banner-mobile.png',
        'https://example.com/banner.png',
        'https://example.com/logo.png'
    ),
    (
        :'otherCommunityID',
        'other-child-links-community',
        'Other Child Links Community',
        'Other community for child link tests',
        'https://example.com/other-banner-mobile.png',
        'https://example.com/other-banner.png',
        'https://example.com/other-logo.png'
    );

-- Group categories
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Technology'),
    (:'otherCommunityGroupCategoryID', :'otherCommunityID', 'Technology');

-- Parent groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values
    (:'activeParentID', :'communityID', :'groupCategoryID', 'Active Parent', 'active-parent', true, false),
    (:'deletedOnlyParentID', :'communityID', :'groupCategoryID', 'Deleted Only Parent', 'deleted-only-parent', true, false),
    (:'inactiveOnlyParentID', :'communityID', :'groupCategoryID', 'Inactive Only Parent', 'inactive-only-parent', true, false),
    (:'otherCommunityParentID', :'otherCommunityID', :'otherCommunityGroupCategoryID', 'Other Community Parent', 'other-community-parent', true, false),
    (:'unrelatedGroupID', :'communityID', :'groupCategoryID', 'Unrelated Group', 'unrelated-group', true, false);

-- Child groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted,

    parent_group_id
) values
    (
        :'activeChildID',
        :'communityID',
        :'groupCategoryID',
        'Active Child',
        'active-child',
        true,
        false,

        :'activeParentID'
    ),
    (
        :'deletedChildID',
        :'communityID',
        :'groupCategoryID',
        'Deleted Child',
        'deleted-child',
        false,
        true,

        :'deletedOnlyParentID'
    ),
    (
        :'inactiveChildID',
        :'communityID',
        :'groupCategoryID',
        'Inactive Child',
        'inactive-child',
        false,
        false,

        :'inactiveOnlyParentID'
    ),
    (
        :'otherCommunityChildID',
        :'otherCommunityID',
        :'otherCommunityGroupCategoryID',
        'Other Community Child',
        'other-community-child',
        true,
        false,

        :'otherCommunityParentID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should detect active non-deleted child links
select is(
    group_has_child_links(:'communityID'::uuid, :'activeParentID'::uuid),
    true,
    'Should detect active non-deleted child links'
);

-- Should detect inactive non-deleted child links
select is(
    group_has_child_links(:'communityID'::uuid, :'inactiveOnlyParentID'::uuid),
    true,
    'Should detect inactive non-deleted child links'
);

-- Should ignore deleted child links
select is(
    group_has_child_links(:'communityID'::uuid, :'deletedOnlyParentID'::uuid),
    false,
    'Should ignore deleted child links'
);

-- Should ignore child links from other communities
select is(
    group_has_child_links(:'communityID'::uuid, :'otherCommunityParentID'::uuid),
    false,
    'Should ignore child links from other communities'
);

-- Should return false when there are no child links
select is(
    group_has_child_links(:'communityID'::uuid, :'unrelatedGroupID'::uuid),
    false,
    'Should return false when there are no child links'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
