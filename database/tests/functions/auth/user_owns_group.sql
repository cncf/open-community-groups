-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set groupID '00000000-0000-0000-0000-000000000021'
\set group2ID '00000000-0000-0000-0000-000000000022'
\set userOrganizerID '00000000-0000-0000-0000-000000000011'
\set userRegularID '00000000-0000-0000-0000-000000000012'
\set userCommunityTeamID '00000000-0000-0000-0000-000000000013'
\set userCommunityTeam2ID '00000000-0000-0000-0000-000000000014'
\set userCommunityTeamPendingID '00000000-0000-0000-0000-000000000015'
\set userGroupTeamPendingID '00000000-0000-0000-0000-000000000016'
\set categoryID '00000000-0000-0000-0000-000000000031'

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
    :'community1ID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'test.example.com',
    'Seattle community for cloud native technologies',
    'https://example.com/logo.png',
    '{}'::jsonb,
    'Cloud Native Seattle Community'
);

-- Second community
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
    :'community2ID',
    'cloud-native-portland',
    'Cloud Native Portland',
    'test2.example.com',
    'Portland community for cloud native technologies',
    'https://example.com/logo2.png',
    '{}'::jsonb,
    'Cloud Native Portland Community'
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
    :'userOrganizerID',
    gen_random_bytes(32),
    :'community1ID',
    'organizer@example.com',
    true,
    'Group Organizer',
    'grouporganizer'
), (
    :'userRegularID',
    gen_random_bytes(32),
    :'community1ID',
    'regular@example.com',
    true,
    'Regular User',
    'regularuser'
), (
    :'userCommunityTeamID',
    gen_random_bytes(32),
    :'community1ID',
    'communityteam@example.com',
    true,
    'Community Team Member',
    'communityteam'
), (
    :'userCommunityTeam2ID',
    gen_random_bytes(32),
    :'community2ID',
    'communityteam2@example.com',
    true,
    'Community Team Member 2',
    'communityteam2'
), (
    :'userCommunityTeamPendingID',
    gen_random_bytes(32),
    :'community1ID',
    'communityteam-pending@example.com',
    true,
    'Community Team Member Pending',
    'communityteampending'
), (
    :'userGroupTeamPendingID',
    gen_random_bytes(32),
    :'community1ID',
    'groupteam-pending@example.com',
    true,
    'Group Team Member Pending',
    'groupteampending'
);

-- Group category
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'categoryID',
    :'community1ID',
    'Technology'
);

-- Groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'community1ID',
    :'categoryID',
    'Kubernetes Study Group',
    'kubernetes-study',
    'Weekly Kubernetes study and discussion group'
), (
    :'group2ID',
    :'community1ID',
    :'categoryID',
    'Docker Study Group',
    'docker-study',
    'Weekly Docker study and discussion group'
);

-- Group team membership
insert into group_team (
    group_id,
    user_id,
    role,
    accepted
) values (
    :'groupID',
    :'userOrganizerID',
    'Organizer',
    true
);

-- Group team pending membership
insert into group_team (
    group_id,
    user_id,
    role,
    accepted
) values (
    :'groupID',
    :'userGroupTeamPendingID',
    'Member',
    false
);

insert into community_team (
    accepted,
    community_id,
    user_id
) values (
    true,
    :'community1ID',
    :'userCommunityTeamID'
), (
    true,
    :'community2ID',
    :'userCommunityTeam2ID'
), (
    false,
    :'community1ID',
    :'userCommunityTeamPendingID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: user_owns_group with group team member should return true
select ok(
    user_owns_group(:'community1ID', :'groupID', :'userOrganizerID'),
    'User in group_team should own the group'
);

-- Test: user_owns_group with non-member should return false
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userRegularID'),
    'User not in group_team should not own the group'
);

-- Test: user_owns_group with pending group team member should return false
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userGroupTeamPendingID'),
    'Pending group team member should not own the group'
);

-- Test: user_owns_group with non-existent user should return false
select ok(
    not user_owns_group(:'community1ID', :'groupID', '00000000-0000-0000-0000-000000000099'::uuid),
    'Non-existent user should not own the group'
);

-- Test: user_owns_group with wrong community should return false
select ok(
    not user_owns_group(:'community2ID', :'groupID', :'userOrganizerID'),
    'Cross-community ownership check should fail even for actual group owner'
);

-- Test: user_owns_group with community team member should return true
select ok(
    user_owns_group(:'community1ID', :'groupID', :'userCommunityTeamID'),
    'Community team member should own any group in their community'
);

-- Test: user_owns_group with community team for any group should return true
select ok(
    user_owns_group(:'community1ID', :'group2ID', :'userCommunityTeamID'),
    'Community team member should own groups they are not explicitly part of'
);

-- Test: user_owns_group with different community team should return false
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userCommunityTeam2ID'),
    'Community team member from different community should not own the group'
);

-- Test: user_owns_group with both team memberships should return true
insert into group_team (group_id, user_id, role, accepted) values (:'group2ID', :'userCommunityTeamID', 'Organizer', true);
select ok(
    user_owns_group(:'community1ID', :'group2ID', :'userCommunityTeamID'),
    'User who is both group team and community team member should own the group'
);

-- Test: user_owns_group with pending community team member should return false
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userCommunityTeamPendingID'),
    'Pending community team member should not own the group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
