-- Tests listing accepted, email-verified community admin user ids.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedAdmin1ID '2c110000-0000-0000-0000-000000000001'
\set acceptedAdmin2ID '2c110000-0000-0000-0000-000000000002'
\set communityID '2c110000-0000-0000-0000-000000000003'
\set groupsManagerID '2c110000-0000-0000-0000-000000000004'
\set missingCommunityID '2c110000-0000-0000-0000-000000000005'
\set unacceptedAdminID '2c110000-0000-0000-0000-000000000006'
\set unverifiedAdminID '2c110000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose eligible admins are listed
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'Community for listing eligible admins',
    'Admin List Community',
    'https://example.com/logo.png',
    'admin-list-community'
);

-- Users covering recipient eligibility states
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username
) values
    (:'acceptedAdmin1ID', gen_random_bytes(32), 'admin1@example.com', true, 'admin1'),
    (:'acceptedAdmin2ID', gen_random_bytes(32), 'admin2@example.com', true, 'admin2'),
    (:'groupsManagerID', gen_random_bytes(32), 'manager@example.com', true, 'manager'),
    (:'unacceptedAdminID', gen_random_bytes(32), 'pending@example.com', true, 'pending-admin'),
    (:'unverifiedAdminID', gen_random_bytes(32), 'unverified@example.com', false, 'unverified-admin');

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
