-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set userRegularID '00000000-0000-0000-0000-000000000012'
\set userTeamMemberID '00000000-0000-0000-0000-000000000011'
\set userTeamMemberPendingID '00000000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    host,
    description,
    header_logo_url,
    theme,
    title
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'test.example.com',
    'Seattle community for cloud native technologies',
    'https://example.com/logo.png',
    '{}'::jsonb,
    'Cloud Native Seattle Community'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    email_verified,
    name,
    username
) values (
    :'userTeamMemberID',
    gen_random_bytes(32),
    :'communityID',
    'teammember@example.com',
    true,
    'Team Member',
    'teammember'
), (
    :'userRegularID',
    gen_random_bytes(32),
    :'communityID',
    'regular@example.com',
    true,
    'Regular User',
    'regularuser'
), (
    :'userTeamMemberPendingID',
    gen_random_bytes(32),
    :'communityID',
    'pending@example.com',
    true,
    'Pending Member',
    'pendingmember'
);

-- Community team membership
insert into community_team (
    accepted,
    community_id,
    user_id
) values (
    true,
    :'communityID',
    :'userTeamMemberID'
), (
    false,
    :'communityID',
    :'userTeamMemberPendingID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return true for user in community_team
select ok(
    user_owns_community(:'communityID', :'userTeamMemberID'),
    'Should return true for user in community_team'
);

-- Should return false for user not in community_team
select ok(
    not user_owns_community(:'communityID', :'userRegularID'),
    'Should return false for user not in community_team'
);

-- Should return false for non-existent user
select ok(
    not user_owns_community(:'communityID', '00000000-0000-0000-0000-000000000099'::uuid),
    'Should return false for non-existent user'
);

-- Should return false for pending team member
select ok(
    not user_owns_community(:'communityID', :'userTeamMemberPendingID'),
    'Should return false for pending team member'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
