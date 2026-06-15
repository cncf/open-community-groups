-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '0d020000-0000-0000-0000-000000000001'
\set inactiveCommunityID '0d020000-0000-0000-0000-000000000002'
\set unknownCommunityID '0d020000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'activeCommunityID',
    'community-name-lookup',
    'Community Name Lookup',
    'Community used for ID lookups',
    'https://example.com/community-name-lookup-banner-mobile.png',
    'https://example.com/community-name-lookup-banner.png',
    'https://example.com/community-name-lookup-logo.png'
);

insert into community (
    community_id,
    name,
    display_name,
    description,
    active,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'inactiveCommunityID',
    'inactive-community-name-lookup',
    'Inactive Community Name Lookup',
    'Inactive community used for ID lookups',
    false,
    'https://example.com/inactive-community-name-lookup-banner-mobile.png',
    'https://example.com/inactive-community-name-lookup-banner.png',
    'https://example.com/inactive-community-name-lookup-logo.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return name for active community
select is(
    get_community_name_by_id(:'activeCommunityID'),
    'community-name-lookup',
    'Should return name for active community'
);

-- Should return null for inactive community
select is(
    get_community_name_by_id(:'inactiveCommunityID'),
    null,
    'Should return null for inactive community'
);

-- Should return null for non-existing community
select is(
    get_community_name_by_id(:'unknownCommunityID'),
    null,
    'Should return null for non-existing community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
