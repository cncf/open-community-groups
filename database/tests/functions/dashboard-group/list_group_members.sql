-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'
\set user4ID '00000000-0000-0000-0000-000000000034'
\set user5ID '00000000-0000-0000-0000-000000000035'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'Community 1', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'categoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (user_id, auth_hash, email, name, username, email_verified, photo_url)
values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'Alice',
        'alice', true, 'https://example.com/alice.png'),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', null,
        'bob', true, 'https://example.com/bob.png'),
    (:'user3ID', gen_random_bytes(32), 'aaron@example.com', null,
        'aaron', true, 'https://example.com/aaron.png'),
    (:'user4ID', gen_random_bytes(32), 'alice2@example.com', 'Alice',
        'alice2', true, 'https://example.com/alice2.png'),
    (:'user5ID', gen_random_bytes(32), 'bobby@example.com', 'Bob',
        'bobby', true, 'https://example.com/bobby.png');

-- Group members
insert into group_member (group_id, user_id, created_at)
values
    (:'groupID', :'user1ID', '2024-01-01 00:00:00+00'),
    (:'groupID', :'user2ID', '2024-01-02 00:00:00+00'),
    (:'groupID', :'user3ID', '2024-01-03 00:00:00+00'),
    (:'groupID', :'user4ID', '2024-01-04 00:00:00+00'),
    (:'groupID', :'user5ID', '2024-01-05 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should order named users by name then username, then unnamed by username
select is(
    list_group_members(:'groupID'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object(
        'members', '[
            {"created_at": 1704067200, "username": "alice", "company": null, "name": "Alice",
                "photo_url": "https://example.com/alice.png", "title": null},
            {"created_at": 1704326400, "username": "alice2", "company": null, "name": "Alice",
                "photo_url": "https://example.com/alice2.png", "title": null},
            {"created_at": 1704412800, "username": "bobby", "company": null, "name": "Bob",
                "photo_url": "https://example.com/bobby.png", "title": null},
            {"created_at": 1704240000, "username": "aaron", "company": null, "name": null,
                "photo_url": "https://example.com/aaron.png", "title": null},
            {"created_at": 1704153600, "username": "bob", "company": null, "name": null,
                "photo_url": "https://example.com/bob.png", "title": null}
        ]'::jsonb,
        'total', 5
    ),
    'Should order named users by name then username, then unnamed by username'
);

-- Should return paginated group members when limit and offset are provided
select is(
    list_group_members(
        :'groupID'::uuid,
        '{"limit": 2, "offset": 2}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', '[
            {"created_at": 1704412800, "username": "bobby", "company": null, "name": "Bob",
                "photo_url": "https://example.com/bobby.png", "title": null},
            {"created_at": 1704240000, "username": "aaron", "company": null, "name": null,
                "photo_url": "https://example.com/aaron.png", "title": null}
        ]'::jsonb,
        'total', 5
    ),
    'Should return paginated group members when limit and offset are provided'
);

-- Should return empty list for non-existing group
select is(
    list_group_members('00000000-0000-0000-0000-000000000099'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object(
        'members', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
