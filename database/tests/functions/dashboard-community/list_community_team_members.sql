-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

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
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    company,
    email,
    name,
    title,
    username,
    email_verified,
    photo_url
) values
    (:'user1ID', gen_random_bytes(32), 'Cloud Corp', 'alice@example.com', 'Alice', 'Principal Engineer', 'alice', true, 'https://example.com/a.png'),
    (:'user2ID', gen_random_bytes(32), null, 'bob@example.com', 'Bob', null, 'bob', true, 'https://example.com/b.png');

-- Team
insert into community_team (accepted, community_id, user_id) values
    (true, :'communityID', :'user2ID'),
    (true, :'communityID', :'user1ID');

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
        'approved_total', 2,
        'members', '[
            {"accepted": true, "user_id": "00000000-0000-0000-0000-000000000011", "username": "alice", "company": "Cloud Corp", "name": "Alice", "photo_url": "https://example.com/a.png", "title": "Principal Engineer"},
            {"accepted": true, "user_id": "00000000-0000-0000-0000-000000000012", "username": "bob", "company": null, "name": "Bob", "photo_url": "https://example.com/b.png", "title": null}
        ]'::jsonb,
        'total', 2
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
        'approved_total', 2,
        'members', '[
            {"accepted": true, "user_id": "00000000-0000-0000-0000-000000000012", "username": "bob", "company": null, "name": "Bob", "photo_url": "https://example.com/b.png", "title": null}
        ]'::jsonb,
        'total', 2
    ),
    'Should return paginated members when limit and offset are provided'
);

-- Should return empty array for unknown community
select is(
    list_community_team_members(
        '00000000-0000-0000-0000-000000000099'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'approved_total', 0,
        'members', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty array for unknown community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
