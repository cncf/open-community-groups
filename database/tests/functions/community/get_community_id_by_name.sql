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

-- Community matched by name lookup
select fx_community(:'activeCommunityID', jsonb_build_object('name', 'community-id-lookup'));

-- Inactive community excluded from name lookup
select fx_community(:'inactiveCommunityID', jsonb_build_object(
    'active', false,
    'name', 'inactive-community-id-lookup'
));

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
