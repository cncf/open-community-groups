-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set user1ID '1c010000-0000-0000-0000-000000000001'
\set user2ID '1c010000-0000-0000-0000-000000000002'
\set user3ID '1c010000-0000-0000-0000-000000000003'
\set user4ID '1c010000-0000-0000-0000-000000000004'
\set user5ID '1c010000-0000-0000-0000-000000000005'
\set user6ID '1c010000-0000-0000-0000-000000000006'
\set user7ID '1c010000-0000-0000-0000-000000000007'
\set user8ID '1c010000-0000-0000-0000-000000000008'
\set user9ID '1c010000-0000-0000-0000-000000000009'
\set userPreRegisteredID '1c010000-0000-0000-0000-00000000000a'
\set userUnverifiedID '1c010000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name,
    photo_url,
    registration_status
)
values
    (
        :'user1ID',
        'hash1',
        'john.doe@example.com',
        true,
        'johndoe',
        'John Doe',
        'https://example.com/john.jpg',
        'registered'
    ),
    (
        :'user2ID',
        'hash2',
        'jane.doe@example.com',
        true,
        'janedoe',
        'Jane Doe',
        'https://example.com/jane.jpg',
        'registered'
    ),
    (
        :'user3ID',
        'hash3',
        'john.smith@example.com',
        true,
        'johnsmith',
        'John Smith',
        null,
        'registered'
    ),
    (
        :'user4ID',
        'hash4',
        'alice@example.com',
        true,
        'alice',
        'Alice Johnson',
        'https://example.com/alice.jpg',
        'registered'
    ),
    (
        :'user5ID',
        'hash5',
        'bob@example.com',
        true,
        'bob',
        null,
        null,
        'registered'
    ),
    (
        :'user6ID',
        'hash6',
        'charlie@example.com',
        true,
        'charlie',
        'Charlie Brown',
        'https://example.com/charlie.jpg',
        'registered'
    ),
    -- Users for testing special characters
    (
        :'user7ID',
        'hash14',
        'usertest@example.com',
        true,
        'user%test',
        'User Percent Test',
        null,
        'registered'
    ),
    (
        :'user8ID',
        'hash15',
        'userspecial@example.com',
        true,
        'user_special',
        'User Underscore',
        null,
        'registered'
    ),
    (
        :'user9ID',
        'hash18',
        'backslash@example.com',
        true,
        'back\slash',
        'Back Slash',
        null,
        'registered'
    ),
    -- Pre-registered users should not appear in regular dashboard search
    (
        :'userPreRegisteredID',
        'hash17',
        'invited@example.com',
        true,
        'invited-user',
        'Invited User',
        null,
        'pre-registered'
    ),
    -- User with unverified email (should not appear in results)
    (
        :'userUnverifiedID',
        'hash16',
        'unverified@example.com',
        false,
        'unverified',
        'Unverified User',
        null,
        'registered'
    );

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
    jsonb_build_array(
        jsonb_build_object(
            'user_id', :'user1ID',
            'username', 'johndoe',
            'name', 'John Doe',
            'photo_url', 'https://example.com/john.jpg'
        ),
        jsonb_build_object(
            'user_id', :'user3ID',
            'username', 'johnsmith',
            'name', 'John Smith',
            'photo_url', null
        )
    ),
    'Should find users by username prefix'
);

-- Should find users by name prefix
select is(
    search_user('jane'),
    jsonb_build_array(
        jsonb_build_object(
            'user_id', :'user2ID',
            'username', 'janedoe',
            'name', 'Jane Doe',
            'photo_url', 'https://example.com/jane.jpg'
        )
    ),
    'Should find users by name prefix'
);

-- Should find users by exact email match
select is(
    search_user('Alice@Example.com'),
    jsonb_build_array(
        jsonb_build_object(
            'user_id', :'user4ID',
            'username', 'alice',
            'name', 'Alice Johnson',
            'photo_url', 'https://example.com/alice.jpg'
        )
    ),
    'Should find users by exact email match (case-insensitive)'
);

-- Should not find users by email prefix
select is(
    search_user('alice@'),
    '[]'::jsonb,
    'Should not find users by email prefix'
);

-- Should treat percent in query as a literal character
select is(
    search_user('user%'),
    jsonb_build_array(
        jsonb_build_object(
            'user_id', :'user7ID',
            'username', 'user%test',
            'name', 'User Percent Test',
            'photo_url', null
        )
    ),
    'Should treat percent in query as a literal character'
);

-- Should treat underscore in query as a literal character
select is(
    search_user('user_'),
    jsonb_build_array(
        jsonb_build_object(
            'user_id', :'user8ID',
            'username', 'user_special',
            'name', 'User Underscore',
            'photo_url', null
        )
    ),
    'Should treat underscore in query as a literal character'
);

-- Should treat backslash in query as a literal character
select is(
    search_user('back\'),
    jsonb_build_array(
        jsonb_build_object(
            'user_id', :'user9ID',
            'username', 'back\slash',
            'name', 'Back Slash',
            'photo_url', null
        )
    ),
    'Should treat backslash in query as a literal character'
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

-- Should not return pre-registered users
select is(
    search_user('invited'),
    '[]'::jsonb,
    'Should not return pre-registered users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
