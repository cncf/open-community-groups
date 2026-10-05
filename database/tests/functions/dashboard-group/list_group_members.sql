-- Tests listing paginated group members.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set caseGroupID '3a210000-0000-0000-0000-00000000000a'
\set communityID '3a210000-0000-0000-0000-000000000001'
\set emptyGroupID '3a210000-0000-0000-0000-00000000000b'
\set groupCategoryID '3a210000-0000-0000-0000-000000000002'
\set groupID '3a210000-0000-0000-0000-000000000003'
\set missingGroupID '3a210000-0000-0000-0000-000000000004'
\set otherGroupID '3a210000-0000-0000-0000-00000000000c'
\set user1ID '3a210000-0000-0000-0000-000000000005'
\set user2ID '3a210000-0000-0000-0000-000000000006'
\set user3ID '3a210000-0000-0000-0000-000000000007'
\set user4ID '3a210000-0000-0000-0000-000000000008'
\set user5ID '3a210000-0000-0000-0000-000000000009'
\set user6ID '3a210000-0000-0000-0000-00000000000d'
\set userCaseLowerID '3a210000-0000-0000-0000-00000000000e'
\set userCaseUnnamedID '3a210000-0000-0000-0000-000000000010'
\set userCaseUpperID '3a210000-0000-0000-0000-00000000000f'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'caseGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'emptyGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

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
select fx_user(:'user6ID', jsonb_build_object(
    'name', 'Dave',
    'username', 'dave-list-group-members'
));

-- Users whose names differ only in case, plus an unnamed user
select fx_user(:'userCaseLowerID', jsonb_build_object(
    'name', 'carol',
    'username', 'zed-carol-list-group-members'
));
select fx_user(:'userCaseUpperID', jsonb_build_object(
    'name', 'CAROL',
    'username', 'amy-carol-list-group-members'
));
select fx_user(:'userCaseUnnamedID', jsonb_build_object(
    'username', 'aa-unnamed-list-group-members'
));

-- Group members
insert into group_member (group_id, user_id, created_at)
values
    (:'groupID', :'user1ID', '2024-01-01 00:00:00+00'),
    (:'groupID', :'user2ID', '2024-01-02 00:00:00+00'),
    (:'groupID', :'user3ID', '2024-01-03 00:00:00+00'),
    (:'groupID', :'user4ID', '2024-01-04 00:00:00+00'),
    (:'groupID', :'user5ID', '2024-01-05 00:00:00+00');

-- Members of the group ordering names that differ only in case
insert into group_member (group_id, user_id, created_at)
values
    (:'caseGroupID', :'userCaseLowerID', '2024-03-01 00:00:00+00'),
    (:'caseGroupID', :'userCaseUnnamedID', '2024-03-01 00:00:00+00'),
    (:'caseGroupID', :'userCaseUpperID', '2024-03-01 00:00:00+00');

-- Members of another group, including a user shared with the main group
insert into group_member (group_id, user_id, created_at)
values
    (:'otherGroupID', :'user1ID', '2024-02-01 00:00:00+00'),
    (:'otherGroupID', :'user6ID', '2024-02-02 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not include members of other groups
select is(
    list_group_members(
        :'otherGroupID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', '[
            {"created_at": 1706745600, "username": "alice1-list-group-members", "company": null, "name": "Alice",
                "photo_url": "https://example.com/u1.png", "title": null},
            {"created_at": 1706832000, "username": "dave-list-group-members", "company": null, "name": "Dave",
                "photo_url": null, "title": null}
        ]'::jsonb,
        'total', 2
    ),
    'Should not include members of other groups'
);

-- Should order null names last and break case ties by username
select is(
    (
        select jsonb_agg(member->>'username' order by position)
        from jsonb_array_elements(
            list_group_members(:'caseGroupID'::uuid, '{"limit": 50, "offset": 0}'::jsonb)::jsonb->'members'
        ) with ordinality as members(member, position)
    ),
    '["amy-carol-list-group-members", "zed-carol-list-group-members", "aa-unnamed-list-group-members"]'::jsonb,
    'Should order null names last and break case ties by username'
);

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

-- Should return an empty page and zero total for an empty group
select is(
    list_group_members(
        :'emptyGroupID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', '[]'::jsonb,
        'total', 0
    ),
    'Should return an empty page and zero total for an empty group'
);

-- Should return the total with an empty page when the offset exceeds it
select is(
    list_group_members(
        :'groupID'::uuid,
        '{"limit": 2, "offset": 10}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', '[]'::jsonb,
        'total', 5
    ),
    'Should return the total with an empty page when the offset exceeds it'
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
