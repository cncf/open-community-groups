-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000051'
\set user1ID '00000000-0000-0000-0000-000000000020'
\set user2ID '00000000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community 1
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community1ID',
    'community-1',
    'Community 1',
    'community1.example.org',
    'Community 1',
    'Test community 1',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Community 2
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community2ID',
    'community-2',
    'Community 2',
    'community2.example.org',
    'Community 2',
    'Test community 2',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Users
insert into "user" (user_id, community_id, email, username, auth_hash, name) values
    (:'user1ID', :'community1ID', 'user1@example.com', 'user1', 'hash1', 'User One'),
    (:'user2ID', :'community2ID', 'user2@example.com', 'user2', 'hash2', 'User Two');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'community1ID');

-- Group (belongs to community 1)
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'community1ID',
    'Test Group',
    'test-group',
    'A test group',
    :'groupCategoryID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when member is from same community as group
select lives_ok(
    format('insert into group_member (group_id, user_id) values (%L, %L)', :'groupID', :'user1ID'),
    'Should succeed when member is from same community as group'
);

-- Should fail when member is from different community
select throws_ok(
    format('insert into group_member (group_id, user_id) values (%L, %L)', :'groupID', :'user2ID'),
    'user not found in community',
    'Should fail when member is from different community'
);

-- Should fail when updating group_member to user from different community
select throws_ok(
    format('update group_member set user_id = %L where group_id = %L', :'user2ID', :'groupID'),
    'user not found in community',
    'Should fail when updating group_member to user from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
