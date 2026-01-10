-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'
\set user3ID '00000000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url
) values
    (:'community1ID', 'alpha-community', 'Alpha Community', 'First community', 'https://example.com/alpha.png'),
    (:'community2ID', 'beta-community', 'Beta Community', 'Second community', 'https://example.com/beta.png');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    name,
    username,
    email_verified
) values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'Alice', 'alice', true),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'Bob', 'bob', true),
    (:'user3ID', gen_random_bytes(32), 'charlie@example.com', 'Charlie', 'charlie', true);

-- Team memberships
-- User 1 is team member of both communities (accepted)
-- User 2 is team member of community1 only (accepted)
-- User 3 is pending team member of community1 (not accepted)
insert into community_team (accepted, community_id, user_id) values
    (true, :'community1ID', :'user1ID'),
    (true, :'community2ID', :'user1ID'),
    (true, :'community1ID', :'user2ID'),
    (false, :'community1ID', :'user3ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return communities for user who is team member of multiple communities
select is(
    list_user_communities(:'user1ID'::uuid)::jsonb,
    '[
        {"community_id": "00000000-0000-0000-0000-000000000001", "community_name": "alpha-community"},
        {"community_id": "00000000-0000-0000-0000-000000000002", "community_name": "beta-community"}
    ]'::jsonb,
    'Should return communities in alphabetical order for user in multiple communities'
);

-- Should return single community for user who is team member of one community
select is(
    list_user_communities(:'user2ID'::uuid)::jsonb,
    '[
        {"community_id": "00000000-0000-0000-0000-000000000001", "community_name": "alpha-community"}
    ]'::jsonb,
    'Should return single community for user in one community'
);

-- Should return empty array for user with pending (not accepted) invitation
select is(
    list_user_communities(:'user3ID'::uuid)::text,
    '[]',
    'Should return empty array for user with pending invitation'
);

-- Should return empty array for unknown user
select is(
    list_user_communities('00000000-0000-0000-0000-000000000099'::uuid)::text,
    '[]',
    'Should return empty array for unknown user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
