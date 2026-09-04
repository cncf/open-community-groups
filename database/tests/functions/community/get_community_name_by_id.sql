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
select fx_community(:'activeCommunityID', jsonb_build_object('name', 'community-name-lookup'));

-- Second community used to verify identifier-specific lookup
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

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
