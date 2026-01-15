-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000031'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set group2ID '00000000-0000-0000-0000-000000000022'
\set groupID '00000000-0000-0000-0000-000000000021'
\set userCommunityTeam2ID '00000000-0000-0000-0000-000000000014'
\set userCommunityTeamID '00000000-0000-0000-0000-000000000013'
\set userCommunityTeamPendingID '00000000-0000-0000-0000-000000000015'
\set userGroupTeamPendingID '00000000-0000-0000-0000-000000000016'
\set userOrganizerID '00000000-0000-0000-0000-000000000011'
\set userRegularID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'community1ID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'Seattle community for cloud native technologies',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Second community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'community2ID',
    'cloud-native-portland',
    'Cloud Native Portland',
    'Portland community for cloud native technologies',
    'https://example.com/logo2.png',
    'https://example.com/banner_mobile2.png',
    'https://example.com/banner2.png'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    name,
    username
) values (
    :'userOrganizerID',
    gen_random_bytes(32),
    'organizer@example.com',
    true,
    'Group Organizer',
    'grouporganizer'
), (
    :'userRegularID',
    gen_random_bytes(32),
    'regular@example.com',
    true,
    'Regular User',
    'regularuser'
), (
    :'userCommunityTeamID',
    gen_random_bytes(32),
    'communityteam@example.com',
    true,
    'Community Team Member',
    'communityteam'
), (
    :'userCommunityTeam2ID',
    gen_random_bytes(32),
    'communityteam2@example.com',
    true,
    'Community Team Member 2',
    'communityteam2'
), (
    :'userCommunityTeamPendingID',
    gen_random_bytes(32),
    'communityteam-pending@example.com',
    true,
    'Community Team Member Pending',
    'communityteampending'
), (
    :'userGroupTeamPendingID',
    gen_random_bytes(32),
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
    'organizer',
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
    'organizer',
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

-- Group team membership for user who is also in community team (second group)
insert into group_team (group_id, user_id, role, accepted)
values (:'group2ID', :'userCommunityTeamID', 'organizer', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return true for user in group_team
select ok(
    user_owns_group(:'community1ID', :'groupID', :'userOrganizerID'),
    'Should return true for user in group_team'
);

-- Should return false for user not in group_team
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userRegularID'),
    'Should return false for user not in group_team'
);

-- Should return false for pending group team member
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userGroupTeamPendingID'),
    'Should return false for pending group team member'
);

-- Should return false for non-existent user
select ok(
    not user_owns_group(:'community1ID', :'groupID', '00000000-0000-0000-0000-000000000099'::uuid),
    'Should return false for non-existent user'
);

-- Should return false for cross-community ownership check
select ok(
    not user_owns_group(:'community2ID', :'groupID', :'userOrganizerID'),
    'Should return false for cross-community ownership check'
);

-- Should return true for community team member
select ok(
    user_owns_group(:'community1ID', :'groupID', :'userCommunityTeamID'),
    'Should return true for community team member'
);

-- Should return true for community team member on any group in their community
select ok(
    user_owns_group(:'community1ID', :'group2ID', :'userCommunityTeamID'),
    'Should return true for community team member on any group in their community'
);

-- Should return false for community team member from different community
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userCommunityTeam2ID'),
    'Should return false for community team member from different community'
);

-- Should return true for user in both group team and community team
select ok(
    user_owns_group(:'community1ID', :'group2ID', :'userCommunityTeamID'),
    'Should return true for user in both group team and community team'
);

-- Should return false for pending community team member
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userCommunityTeamPendingID'),
    'Should return false for pending community team member'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
