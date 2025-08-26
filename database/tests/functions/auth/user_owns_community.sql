-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set userTeamMemberID '00000000-0000-0000-0000-000000000011'
\set userRegularID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community (test community for ownership checks)
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

-- Users with different permission levels
-- userTeamMemberID: User with community team membership
-- userRegularID: Regular user without team membership
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
);

-- Community team membership (grants ownership)
insert into community_team (
    community_id,
    user_id,
    role
) values (
    :'communityID',
    :'userTeamMemberID',
    'Member'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- User in community_team should own the community
select ok(
    user_owns_community(:'communityID', :'userTeamMemberID'),
    'User in community_team should own the community'
);

-- User not in community_team should not own the community
select ok(
    not user_owns_community(:'communityID', :'userRegularID'),
    'User not in community_team should not own the community'
);

-- Non-existent user should not own the community
select ok(
    not user_owns_community(:'communityID', '00000000-0000-0000-0000-000000000099'::uuid),
    'Non-existent user should not own the community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
