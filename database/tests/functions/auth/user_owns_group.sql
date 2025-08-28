-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

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
\set categoryID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- First community for testing group ownership
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

-- Second community for cross-community ownership testing

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

-- Users with different permission levels
-- userOrganizerID: User with group organizer role
-- userRegularID: Regular user without special permissions
-- userCommunityTeamID: User with community team role
-- userCommunityTeam2ID: User with community team role in community2
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
);

-- Group category for test group
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'categoryID',
    :'community1ID',
    'Technology'
);

-- Test groups for ownership verification
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

-- Group team membership (grants ownership to organizer)
insert into group_team (
    group_id,
    user_id,
    role
) values (
    :'groupID',
    :'userOrganizerID',
    'Organizer'
);

-- Community team membership (grants access to all groups in community)
insert into community_team (
    community_id,
    user_id,
    role
) values (
    :'community1ID',
    :'userCommunityTeamID',
    'Admin'
), (
    :'community2ID',
    :'userCommunityTeam2ID',
    'Admin'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- User in group_team should own the group
select ok(
    user_owns_group(:'community1ID', :'groupID', :'userOrganizerID'),
    'User in group_team should own the group'
);

-- User not in group_team should not own the group
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userRegularID'),
    'User not in group_team should not own the group'
);

-- Non-existent user should not own the group
select ok(
    not user_owns_group(:'community1ID', :'groupID', '00000000-0000-0000-0000-000000000099'::uuid),
    'Non-existent user should not own the group'
);

-- Cross-community check should fail even for group owner
select ok(
    not user_owns_group(:'community2ID', :'groupID', :'userOrganizerID'),
    'Cross-community ownership check should fail even for actual group owner'
);

-- Community team member should own any group in their community
select ok(
    user_owns_group(:'community1ID', :'groupID', :'userCommunityTeamID'),
    'Community team member should own any group in their community'
);

-- Community team member should own groups they are not explicitly part of
select ok(
    user_owns_group(:'community1ID', :'group2ID', :'userCommunityTeamID'),
    'Community team member should own groups they are not explicitly part of'
);

-- Community team member from different community should not own the group
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userCommunityTeam2ID'),
    'Community team member from different community should not own the group'
);

-- User who is both group team and community team member should own the group
insert into group_team (group_id, user_id, role) values (:'group2ID', :'userCommunityTeamID', 'Organizer');
select ok(
    user_owns_group(:'community1ID', :'group2ID', :'userCommunityTeamID'),
    'User who is both group team and community team member should own the group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
