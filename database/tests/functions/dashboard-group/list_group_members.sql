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

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID', jsonb_build_object(
    'name', 'Alice',
    'photo_url', 'https://example.com/u1.png',
    'username', 'alice1-list-group-members'
));
select fx_user(:'user2ID', jsonb_build_object(
    'photo_url', 'https://example.com/u2.png',
    'username', 'bob-list-group-members'
));
select fx_user(:'user3ID', jsonb_build_object(
    'photo_url', 'https://example.com/u3.png',
    'username', 'aaron'
));
select fx_user(:'user4ID', jsonb_build_object(
    'name', 'Alice',
    'photo_url', 'https://example.com/u4.png',
    'username', 'alice2-list-group-members'
));
select fx_user(:'user5ID', jsonb_build_object(
    'name', 'Bob',
    'photo_url', 'https://example.com/u5.png',
    'username', 'bobby'
));

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
            {"created_at": 1704067200, "username": "alice1-list-group-members", "company": null, "name": "Alice",
                "photo_url": "https://example.com/u1.png", "title": null},
            {"created_at": 1704326400, "username": "alice2-list-group-members", "company": null, "name": "Alice",
                "photo_url": "https://example.com/u4.png", "title": null},
            {"created_at": 1704412800, "username": "bobby", "company": null, "name": "Bob",
                "photo_url": "https://example.com/u5.png", "title": null},
            {"created_at": 1704240000, "username": "aaron", "company": null, "name": null,
                "photo_url": "https://example.com/u3.png", "title": null},
            {"created_at": 1704153600, "username": "bob-list-group-members", "company": null, "name": null,
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
