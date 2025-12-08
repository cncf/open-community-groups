-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'
\set user3ID '00000000-0000-0000-0000-000000000013'
\set user4ID '00000000-0000-0000-0000-000000000014'
\set user5ID '00000000-0000-0000-0000-000000000015'
\set user6ID '00000000-0000-0000-0000-000000000016'
\set user7ID '00000000-0000-0000-0000-000000000017'
\set user8ID '00000000-0000-0000-0000-000000000018'
\set user9ID '00000000-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'test.example.org',
    'Test Community',
    'A test community for user search',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Community (other)
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community2ID',
    'other-community',
    'Other Community',
    'other.example.org',
    'Other Community',
    'Another community',
    'https://example.com/logo2.png',
    '{}'::jsonb
);

-- User
insert into "user" (user_id, username, email, auth_hash, community_id, name, photo_url)
values 
    (:'user1ID', 'johndoe', 'john.doe@example.com', 'hash1', :'communityID', 'John Doe', 'https://example.com/john.jpg'),
    (:'user2ID', 'janedoe', 'jane.doe@example.com', 'hash2', :'communityID', 'Jane Doe', 'https://example.com/jane.jpg'),
    (:'user3ID', 'johnsmith', 'john.smith@example.com', 'hash3', :'communityID', 'John Smith', null),
    (:'user4ID', 'alice', 'alice@example.com', 'hash4', :'communityID', 'Alice Johnson', 'https://example.com/alice.jpg'),
    (:'user5ID', 'bob', 'bob@example.com', 'hash5', :'communityID', null, null),
    (:'user6ID', 'charlie', 'charlie@example.com', 'hash6', :'communityID', 'Charlie Brown', 'https://example.com/charlie.jpg'),
    -- User in different community (should not appear in results)
    (:'user7ID', 'johndoe', 'john.other@example.com', 'hash7', :'community2ID', 'John from Other', 'https://example.com/other.jpg');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should find users by username prefix
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'john'),
    '[
        {
            "user_id": "00000000-0000-0000-0000-000000000011",
            "username": "johndoe",
            "name": "John Doe",
            "photo_url": "https://example.com/john.jpg"
        },
        {
            "user_id": "00000000-0000-0000-0000-000000000013",
            "username": "johnsmith",
            "name": "John Smith",
            "photo_url": null
        }
    ]'::jsonb,
    'Should find users by username prefix'
);

-- Should find users by name prefix
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'jane'),
    '[
        {
            "user_id": "00000000-0000-0000-0000-000000000012",
            "username": "janedoe",
            "name": "Jane Doe",
            "photo_url": "https://example.com/jane.jpg"
        }
    ]'::jsonb,
    'Should find users by name prefix'
);

-- Should find users by email prefix
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'alice@'),
    '[
        {
            "user_id": "00000000-0000-0000-0000-000000000014",
            "username": "alice",
            "name": "Alice Johnson",
            "photo_url": "https://example.com/alice.jpg"
        }
    ]'::jsonb,
    'Should find users by email prefix'
);

-- Should cap results to maximum of 5
insert into "user" (username, email, auth_hash, community_id, name)
values 
    ('test1', 'test1@example.com', 'hash8', :'communityID', 'Test User 1'),
    ('test2', 'test2@example.com', 'hash9', :'communityID', 'Test User 2'),
    ('test3', 'test3@example.com', 'hash10', :'communityID', 'Test User 3'),
    ('test4', 'test4@example.com', 'hash11', :'communityID', 'Test User 4'),
    ('test5', 'test5@example.com', 'hash12', :'communityID', 'Test User 5'),
    ('test6', 'test6@example.com', 'hash13', :'communityID', 'Test User 6');

select is(
    jsonb_array_length(search_user('00000000-0000-0000-0000-000000000001'::uuid, 'test')),
    5,
    'Should return maximum 5 results'
);

-- Should return no results for non-matching query
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'nonexistent'),
    '[]'::jsonb,
    'Should return no results for non-matching query'
);

-- Should only return users from the specified community
select is(
    search_user('00000000-0000-0000-0000-000000000002'::uuid, 'john'),
    '[
        {
            "user_id": "00000000-0000-0000-0000-000000000017",
            "username": "johndoe",
            "name": "John from Other",
            "photo_url": "https://example.com/other.jpg"
        }
    ]'::jsonb,
    'Should only return users from the specified community'
);

-- Should return no results for empty query
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, ''),
    '[]'::jsonb,
    'Should return no results for empty query'
);

-- Should treat % and _ as literal characters, not wildcards
insert into "user" (user_id, username, email, auth_hash, community_id, name)
values 
    (:'user8ID', 'user%test', 'usertest@example.com', 'hash14', :'communityID', 'User Percent Test'),
    (:'user9ID', 'user_special', 'userspecial@example.com', 'hash15', :'communityID', 'User Underscore');

select is(
    jsonb_array_length(search_user('00000000-0000-0000-0000-000000000001'::uuid, 'user%')) = 1
    and jsonb_array_length(search_user('00000000-0000-0000-0000-000000000001'::uuid, 'user_')) = 1
    and search_user('00000000-0000-0000-0000-000000000001'::uuid, 'user%') @> '[{"username": "user%test"}]'::jsonb
    and search_user('00000000-0000-0000-0000-000000000001'::uuid, 'user_') @> '[{"username": "user_special"}]'::jsonb,
    true,
    'Should treat % and _ as literal characters, not wildcards'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
