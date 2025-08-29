-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'
\set user3ID '00000000-0000-0000-0000-000000000013'
\set user4ID '00000000-0000-0000-0000-000000000014'
\set user5ID '00000000-0000-0000-0000-000000000015'
\set user6ID '00000000-0000-0000-0000-000000000016'
\set user7ID '00000000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for testing user search
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

-- Second community for isolation testing
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

-- Users for testing
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

-- Test 1: Search by username prefix
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'john'),
    '[
        {
            "username": "johndoe",
            "name": "John Doe",
            "photo_url": "https://example.com/john.jpg"
        },
        {
            "username": "johnsmith",
            "name": "John Smith",
            "photo_url": null
        }
    ]'::jsonb,
    'search_user should find users by username prefix'
);

-- Test 2: Search by name prefix
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'jane'),
    '[
        {
            "username": "janedoe",
            "name": "Jane Doe",
            "photo_url": "https://example.com/jane.jpg"
        }
    ]'::jsonb,
    'search_user should find users by name prefix'
);

-- Test 3: Search by email prefix
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'alice@'),
    '[
        {
            "username": "alice",
            "name": "Alice Johnson",
            "photo_url": "https://example.com/alice.jpg"
        }
    ]'::jsonb,
    'search_user should find users by email prefix'
);

-- Test 4: Case-insensitive matching
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'JOHN'),
    '[
        {
            "username": "johndoe",
            "name": "John Doe",
            "photo_url": "https://example.com/john.jpg"
        },
        {
            "username": "johnsmith",
            "name": "John Smith",
            "photo_url": null
        }
    ]'::jsonb,
    'search_user should match case-insensitively'
);

-- Test 5: Limit to 5 results
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
    'search_user should return maximum 5 results'
);

-- Test 6: No results for non-matching query
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'nonexistent'),
    '[]'::jsonb,
    'search_user should return no results for non-matching query'
);

-- Test 7: Community isolation
select is(
    search_user('00000000-0000-0000-0000-000000000002'::uuid, 'john'),
    '[
        {
            "username": "johndoe",
            "name": "John from Other",
            "photo_url": "https://example.com/other.jpg"
        }
    ]'::jsonb,
    'search_user should only return users from the specified community'
);

-- Test 8: Empty query returns no results
select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, ''),
    '[]'::jsonb,
    'search_user should return no results for empty query'
);

-- Test 9: SQL injection prevention - percent character
insert into "user" (username, email, auth_hash, community_id, name)
values ('user%test', 'usertest@example.com', 'hash14', :'communityID', 'User Percent Test');

select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'user%'),
    '[
        {
            "username": "user%test",
            "name": "User Percent Test",
            "photo_url": null
        }
    ]'::jsonb,
    'search_user should treat % as literal character, not wildcard'
);

-- Test 10: SQL injection prevention - underscore character
insert into "user" (username, email, auth_hash, community_id, name)
values ('user_special', 'userspecial@example.com', 'hash15', :'communityID', 'User Underscore');

select is(
    search_user('00000000-0000-0000-0000-000000000001'::uuid, 'user_'),
    '[
        {
            "username": "user_special",
            "name": "User Underscore",
            "photo_url": null
        }
    ]'::jsonb,
    'search_user should treat _ as literal character, not wildcard'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;