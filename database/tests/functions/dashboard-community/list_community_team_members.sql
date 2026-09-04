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

-- Baseline community
select fx_community(:'communityID');

select fx_user(:'user1ID', jsonb_build_object(
    'company', 'Cloud Corp',
    'name', 'Alice',
    'photo_url', 'https://example.com/users/alice.png',
    'title', 'Principal Engineer',
    'username', 'alice-team-members'
));
-- user
select fx_user(:'user2ID', jsonb_build_object(
    'name', 'Bob',
    'photo_url', 'https://example.com/users/bob.png',
    'username', 'bob-team-members'
));

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
                    "username": "alice-team-members",
                    "company": "Cloud Corp",
                    "name": "Alice",
                    "photo_url": "https://example.com/users/alice.png",
                    "title": "Principal Engineer"
                },
                {
                    "accepted": true,
                    "role": "viewer",
                    "user_id": "%s",
                    "username": "bob-team-members",
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
                    "username": "bob-team-members",
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
