-- Tests listing accepted, email-verified community admin user ids.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedAdmin1ID '3a000000-0000-0000-0000-000000000001'
\set acceptedAdmin2ID '3a000000-0000-0000-0000-000000000002'
\set communityID '3a000000-0000-0000-0000-000000000003'
\set groupsManagerID '3a000000-0000-0000-0000-000000000004'
\set missingCommunityID '3a000000-0000-0000-0000-000000000005'
\set unacceptedAdminID '3a000000-0000-0000-0000-000000000006'
\set unverifiedAdminID '3a000000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and users
select fx_community(:'communityID');
select fx_user(:'acceptedAdmin1ID');
select fx_user(:'acceptedAdmin2ID');
select fx_user(:'unacceptedAdminID');

-- Users covering recipient eligibility states
select fx_user(:'groupsManagerID', jsonb_build_object('username', 'manager'));
select fx_user(:'unverifiedAdminID', jsonb_build_object('email_verified', false));

-- Community team memberships covering recipient eligibility states
insert into community_team (community_id, user_id, accepted, role) values
    (:'communityID', :'acceptedAdmin1ID', true, 'admin'),
    (:'communityID', :'acceptedAdmin2ID', true, 'admin'),
    (:'communityID', :'groupsManagerID', true, 'groups-manager'),
    (:'communityID', :'unacceptedAdminID', false, 'admin'),
    (:'communityID', :'unverifiedAdminID', true, 'admin');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return accepted, verified admin user ids ordered by user id
select is(
    list_community_admin_ids(:'communityID'::uuid),
    array[:'acceptedAdmin1ID'::uuid, :'acceptedAdmin2ID'::uuid],
    'Should return accepted, verified admin user ids ordered by user id'
);

-- Should return an empty list for an unknown community
select is(
    list_community_admin_ids(:'missingCommunityID'::uuid),
    array[]::uuid[],
    'Should return an empty list for an unknown community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
