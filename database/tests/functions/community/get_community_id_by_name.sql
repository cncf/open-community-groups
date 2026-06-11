-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '0d010000-0000-0000-0000-000000000001'
\set inactiveCommunityID '0d010000-0000-0000-0000-000000000002'

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
    'community-id-lookup',
    'Community ID Lookup',
    'Community used for name lookups',
    'https://example.com/community-id-lookup-banner-mobile.png',
    'https://example.com/community-id-lookup-banner.png',
    'https://example.com/community-id-lookup-logo.png'
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
    'inactive-community-id-lookup',
    'Inactive Community ID Lookup',
    'Inactive community used for name lookups',
    false,
    'https://example.com/inactive-community-id-lookup-banner-mobile.png',
    'https://example.com/inactive-community-id-lookup-banner.png',
    'https://example.com/inactive-community-id-lookup-logo.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return community_id for active community
select is(
    get_community_id_by_name('community-id-lookup'),
    :'activeCommunityID'::uuid,
    'Should return community_id for active community'
);

-- Should return null for inactive community
select is(
    get_community_id_by_name('inactive-community-id-lookup'),
    null,
    'Should return null for inactive community'
);

-- Should return null for non-existing community
select is(
    get_community_id_by_name('non-existing-community'),
    null,
    'Should return null for non-existing community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
