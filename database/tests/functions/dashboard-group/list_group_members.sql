-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a210000-0000-0000-0000-000000000001'
\set groupCategoryID '3a210000-0000-0000-0000-000000000002'
\set groupID '3a210000-0000-0000-0000-000000000003'
\set missingGroupID '3a210000-0000-0000-0000-000000000004'
\set user1ID '3a210000-0000-0000-0000-000000000005'
\set user2ID '3a210000-0000-0000-0000-000000000006'
\set user3ID '3a210000-0000-0000-0000-000000000007'
\set user4ID '3a210000-0000-0000-0000-000000000008'
\set user5ID '3a210000-0000-0000-0000-000000000009'

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
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name,
    photo_url
) values (
    :'user1ID',
    gen_random_bytes(32),
    'alice@example.com',
    true,
    'alice',
    'Alice',
    'https://example.com/u1.png'
), (
    :'user2ID',
    gen_random_bytes(32),
    'bob@example.com',
    true,
    'bob',
    null,
    'https://example.com/u2.png'
), (
    :'user3ID',
    gen_random_bytes(32),
    'aaron@example.com',
    true,
    'aaron',
    null,
    'https://example.com/u3.png'
), (
    :'user4ID',
    gen_random_bytes(32),
    'alice2@example.com',
    true,
    'alice2',
    'Alice',
    'https://example.com/u4.png'
), (
    :'user5ID',
    gen_random_bytes(32),
    'bobby@example.com',
    true,
    'bobby',
    'Bob',
    'https://example.com/u5.png'
);

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
    list_group_members(
        :'groupID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', '[
            {"created_at": 1704067200, "username": "alice", "company": null, "name": "Alice",
                "photo_url": "https://example.com/u1.png", "title": null},
            {"created_at": 1704326400, "username": "alice2", "company": null, "name": "Alice",
                "photo_url": "https://example.com/u4.png", "title": null},
            {"created_at": 1704412800, "username": "bobby", "company": null, "name": "Bob",
                "photo_url": "https://example.com/u5.png", "title": null},
            {"created_at": 1704240000, "username": "aaron", "company": null, "name": null,
                "photo_url": "https://example.com/u3.png", "title": null},
            {"created_at": 1704153600, "username": "bob", "company": null, "name": null,
                "photo_url": "https://example.com/u2.png", "title": null}
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
                "photo_url": "https://example.com/u5.png", "title": null},
            {"created_at": 1704240000, "username": "aaron", "company": null, "name": null,
                "photo_url": "https://example.com/u3.png", "title": null}
        ]'::jsonb,
        'total', 5
    ),
    'Should return paginated group members when limit and offset are provided'
);

-- Should return empty list for non-existing group
select is(
    list_group_members(
        :'missingGroupID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb,
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
