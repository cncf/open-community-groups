-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c100000-0000-0000-0000-000000000001'
\set unknownCommunityID '2c100000-0000-0000-0000-000000000002'
\set user1ID '2c100000-0000-0000-0000-000000000003'
\set user2ID '2c100000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'team-members-community',
    'Team Members Community',
    'Community for listing team members',
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
    company,
    name,
    photo_url,
    title
) values
    (
        :'user1ID',
        gen_random_bytes(32),
        'alice@example.com',
        true,
        'alice',
        'Cloud Corp',
        'Alice',
        'https://example.com/users/alice.png',
        'Principal Engineer'
    ),
    (
        :'user2ID',
        gen_random_bytes(32),
        'bob@example.com',
        true,
        'bob',
        null,
        'Bob',
        'https://example.com/users/bob.png',
        null
    );

-- Community team
insert into community_team (community_id, user_id, accepted, role) values
    (:'communityID', :'user2ID', true, 'viewer'),
    (:'communityID', :'user1ID', true, 'admin');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return expected members in alphabetical order including accepted flag
select is(
    list_community_team_members(
        :'communityID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', format(
            $json$
            [
                {
                    "accepted": true,
                    "role": "admin",
                    "user_id": "%s",
                    "username": "alice",
                    "company": "Cloud Corp",
                    "name": "Alice",
                    "photo_url": "https://example.com/users/alice.png",
                    "title": "Principal Engineer"
                },
                {
                    "accepted": true,
                    "role": "viewer",
                    "user_id": "%s",
                    "username": "bob",
                    "company": null,
                    "name": "Bob",
                    "photo_url": "https://example.com/users/bob.png",
                    "title": null
                }
            ]
            $json$,
            :'user1ID',
            :'user2ID'
        )::jsonb,
        'total', 2,
        'total_accepted', 2,
        'total_admins_accepted', 1
    ),
    'Should return expected members in alphabetical order including accepted flag'
);

-- Should return paginated members when limit and offset are provided
select is(
    list_community_team_members(
        :'communityID'::uuid,
        '{"limit": 1, "offset": 1}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', format(
            $json$
            [
                {
                    "accepted": true,
                    "role": "viewer",
                    "user_id": "%s",
                    "username": "bob",
                    "company": null,
                    "name": "Bob",
                    "photo_url": "https://example.com/users/bob.png",
                    "title": null
                }
            ]
            $json$,
            :'user2ID'
        )::jsonb,
        'total', 2,
        'total_accepted', 2,
        'total_admins_accepted', 1
    ),
    'Should return paginated members when limit and offset are provided'
);

-- Should return empty array for unknown community
select is(
    list_community_team_members(
        :'unknownCommunityID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', '[]'::jsonb,
        'total', 0,
        'total_accepted', 0,
        'total_admins_accepted', 0
    ),
    'Should return empty array for unknown community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
