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

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when team member is from same community
select lives_ok(
    format('insert into community_team (community_id, user_id) values (%L, %L)', :'community1ID', :'user1ID'),
    'Should succeed when team member is from same community'
);

-- Should fail when team member is from different community
select throws_ok(
    format('insert into community_team (community_id, user_id) values (%L, %L)', :'community1ID', :'user2ID'),
    format('team member user %s not found in community', :'user2ID'),
    'Should fail when team member is from different community'
);

-- Should fail when updating community_team to user from different community
select throws_ok(
    format('update community_team set user_id = %L where community_id = %L', :'user2ID', :'community1ID'),
    format('team member user %s not found in community', :'user2ID'),
    'Should fail when updating community_team to user from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
