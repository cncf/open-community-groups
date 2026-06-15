-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '4a0a0000-0000-0000-0000-000000000001'
\set community2ID '4a0a0000-0000-0000-0000-000000000002'
\set user1ID '4a0a0000-0000-0000-0000-000000000003'
\set user2ID '4a0a0000-0000-0000-0000-000000000004'
\set user3ID '4a0a0000-0000-0000-0000-000000000005'

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
    'community-one',
    'Community One',
    'First community with pending invitations',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'community2ID',
    'community-two',
    'Community Two',
    'Second community with pending invitations',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'user1ID',
    gen_random_bytes(32),
    'u1@example.com',
    true,
    'u1',
    'User One'
), (
    :'user2ID',
    gen_random_bytes(32),
    'u2@example.com',
    true,
    'u2',
    'User Two'
), (
    :'user3ID',
    gen_random_bytes(32),
    'u3@example.com',
    true,
    'u3',
    'User Three'
);

-- Invitations
insert into community_team (
    accepted, community_id, created_at, role, user_id
) values
    (false, :'community1ID', '2024-01-02 03:04:05+00', 'admin', :'user1ID'),
    (false, :'community2ID', '2024-01-03 03:04:05+00', 'viewer', :'user1ID'),
    (false, :'community2ID', current_timestamp, 'viewer', :'user3ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all pending invitations for a user across all communities
select results_eq(
    format(
        $$
            select list_user_community_team_invitations(%L::uuid)::jsonb
        $$,
        :'user1ID'
    ),
    format(
        $$
            values ('
                [
                    {
                        "community_id": "%s",
                        "community_name": "community-two",
                        "role": "viewer",
                        "created_at": 1704251045
                    },
                    {
                        "community_id": "%s",
                        "community_name": "community-one",
                        "role": "admin",
                        "created_at": 1704164645
                    }
                ]
            '::jsonb)
        $$,
        :'community2ID',
        :'community1ID'
    ),
    'Should return all pending invitations for the user ordered by created_at desc'
);

-- Should return empty array when user has no pending invitations
select results_eq(
    format(
        $$
            select list_user_community_team_invitations(%L::uuid)::jsonb
        $$,
        :'user2ID'
    ),
    $$ values ('[]'::jsonb) $$,
    'Should return empty array when there are no pending invitations'
);

-- Should not return accepted invitations
update community_team set accepted = true
where community_id = :'community1ID' and user_id = :'user1ID';
select results_eq(
    format(
        $$
            select list_user_community_team_invitations(%L::uuid)::jsonb
        $$,
        :'user1ID'
    ),
    format(
        $$
            values ('
                [
                    {
                        "community_id": "%s",
                        "community_name": "community-two",
                        "role": "viewer",
                        "created_at": 1704251045
                    }
                ]
            '::jsonb)
        $$,
        :'community2ID'
    ),
    'Should not return accepted invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
