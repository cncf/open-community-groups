-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    display_name,
    host,
    name,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'communityID',
    'Cloud Native Seattle',
    'seattle.cloudnative.org',
    'cloud-native-seattle',
    'Cloud Native Seattle Community',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    name,
    username,
    email_verified,
    photo_url
) values
    (:'user1ID', gen_random_bytes(32), :'communityID', 'alice@example.com', 'Alice', 'alice', true, 'https://example.com/a.png'),
    (:'user2ID', gen_random_bytes(32), :'communityID', 'bob@example.com', 'Bob', 'bob', true, 'https://example.com/b.png');

-- Team
insert into community_team (community_id, user_id) values
    (:'communityID', :'user2ID'),
    (:'communityID', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: list_community_team_members should return both members ordered by name
select is(
    list_community_team_members(:'communityID'::uuid)::jsonb,
    '[
        {"user_id": "00000000-0000-0000-0000-000000000011", "username": "alice", "name": "Alice", "photo_url": "https://example.com/a.png"},
        {"user_id": "00000000-0000-0000-0000-000000000012", "username": "bob", "name": "Bob", "photo_url": "https://example.com/b.png"}
    ]'::jsonb,
    'list_community_team_members should return expected members in alphabetical order'
);

-- Test: list_community_team_members should return empty array when no members
select is(
    list_community_team_members('00000000-0000-0000-0000-000000000099'::uuid)::text,
    '[]',
    'list_community_team_members should return empty array for unknown community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;

