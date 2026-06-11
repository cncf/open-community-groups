-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '2c130000-0000-0000-0000-000000000001'
\set community2ID '2c130000-0000-0000-0000-000000000002'
\set unknownUserID '2c130000-0000-0000-0000-000000000003'
\set user1ID '2c130000-0000-0000-0000-000000000004'
\set user2ID '2c130000-0000-0000-0000-000000000005'
\set user3ID '2c130000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'community1ID',
    'alpha-community',
    'Alpha Community',
    'First community',
    'https://example.com/alpha-banner-mobile.png',
    'https://example.com/alpha-banner.png',
    'https://example.com/alpha.png'
), (
    :'community2ID',
    'beta-community',
    'Beta Community',
    'Second community',
    'https://example.com/beta-banner-mobile.png',
    'https://example.com/beta-banner.png',
    'https://example.com/beta.png'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', true, 'alice', 'Alice'),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', true, 'bob', 'Bob'),
    (:'user3ID', gen_random_bytes(32), 'charlie@example.com', true, 'charlie', 'Charlie');

-- Team memberships
-- User 1 is team member of both communities (accepted)
-- User 2 is team member of community1 only (accepted)
-- User 3 is pending team member of community1 (not accepted)
insert into community_team (community_id, user_id, accepted, role) values
    (:'community1ID', :'user1ID', true, 'admin'),
    (:'community2ID', :'user1ID', true, 'admin'),
    (:'community1ID', :'user2ID', true, 'admin'),
    (:'community1ID', :'user3ID', false, 'viewer');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return communities for user who is team member of multiple communities
select is(
    list_user_communities(:'user1ID'::uuid)::jsonb,
    (select json_agg(get_community_summary(community_id) order by name) from community)::jsonb,
    'Should return communities in alphabetical order for user in multiple communities'
);

-- Should return single community for user who is team member of one community
select is(
    list_user_communities(:'user2ID'::uuid)::jsonb,
    json_build_array(get_community_summary(:'community1ID'::uuid))::jsonb,
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
    list_user_communities(:'unknownUserID'::uuid)::text,
    '[]',
    'Should return empty array for unknown user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
