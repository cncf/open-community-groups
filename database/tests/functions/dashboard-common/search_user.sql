-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'
\set user3ID '00000000-0000-0000-0000-000000000013'
\set user4ID '00000000-0000-0000-0000-000000000014'
\set user5ID '00000000-0000-0000-0000-000000000015'
\set user6ID '00000000-0000-0000-0000-000000000016'
\set user7ID '00000000-0000-0000-0000-000000000017'
\set user8ID '00000000-0000-0000-0000-000000000018'
\set userUnverifiedID '00000000-0000-0000-0000-000000000020'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, username, email, email_verified, auth_hash, name, photo_url)
values
    (:'user1ID', 'johndoe', 'john.doe@example.com', true, 'hash1', 'John Doe', 'https://example.com/john.jpg'),
    (:'user2ID', 'janedoe', 'jane.doe@example.com', true, 'hash2', 'Jane Doe', 'https://example.com/jane.jpg'),
    (:'user3ID', 'johnsmith', 'john.smith@example.com', true, 'hash3', 'John Smith', null),
    (:'user4ID', 'alice', 'alice@example.com', true, 'hash4', 'Alice Johnson', 'https://example.com/alice.jpg'),
    (:'user5ID', 'bob', 'bob@example.com', true, 'hash5', null, null),
    (:'user6ID', 'charlie', 'charlie@example.com', true, 'hash6', 'Charlie Brown', 'https://example.com/charlie.jpg'),
    -- Users for testing special characters
    (:'user7ID', 'user%test', 'usertest@example.com', true, 'hash14', 'User Percent Test', null),
    (:'user8ID', 'user_special', 'userspecial@example.com', true, 'hash15', 'User Underscore', null),
    -- User with unverified email (should not appear in results)
    (:'userUnverifiedID', 'unverified', 'unverified@example.com', false, 'hash16', 'Unverified User', null);

-- User (for testing max results limit)
insert into "user" (username, email, email_verified, auth_hash, name)
values
    ('test1', 'test1@example.com', true, 'hash8', 'Test User 1'),
    ('test2', 'test2@example.com', true, 'hash9', 'Test User 2'),
    ('test3', 'test3@example.com', true, 'hash10', 'Test User 3'),
    ('test4', 'test4@example.com', true, 'hash11', 'Test User 4'),
    ('test5', 'test5@example.com', true, 'hash12', 'Test User 5'),
    ('test6', 'test6@example.com', true, 'hash13', 'Test User 6');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should find users by username prefix
select is(
    search_user('john'),
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
    search_user('jane'),
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
    search_user('alice@'),
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
select is(
    jsonb_array_length(search_user('test')),
    5,
    'Should return maximum 5 results'
);

-- Should return no results for non-matching query
select is(
    search_user('nonexistent'),
    '[]'::jsonb,
    'Should return no results for non-matching query'
);

-- Should return no results for empty query
select is(
    search_user(''),
    '[]'::jsonb,
    'Should return no results for empty query'
);

-- Should not return users with unverified email
select is(
    search_user('unverified'),
    '[]'::jsonb,
    'Should not return users with unverified email'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
