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

-- Baseline users
select fx_user(:'user5ID');
select fx_user(:'user6ID');

-- Users for testing max results limit
select fx_user(gen_random_uuid(), jsonb_build_object('username', 'test1'));
select fx_user(gen_random_uuid(), jsonb_build_object('username', 'test2'));
select fx_user(gen_random_uuid(), jsonb_build_object('username', 'test3'));
select fx_user(gen_random_uuid(), jsonb_build_object('username', 'test4'));
select fx_user(gen_random_uuid(), jsonb_build_object('username', 'test5'));
select fx_user(gen_random_uuid(), jsonb_build_object('username', 'test6'));

-- Users used by search scenarios
select fx_user(:'user1ID', jsonb_build_object(
    'name', 'John Doe',
    'photo_url', 'https://example.com/john.jpg',
    'username', 'johndoe'
));
select fx_user(:'user2ID', jsonb_build_object(
    'name', 'Jane Doe',
    'photo_url', 'https://example.com/jane.jpg',
    'username', 'janedoe'
));
select fx_user(:'user3ID', jsonb_build_object(
    'name', 'John Smith',
    'username', 'johnsmith'
));
select fx_user(:'user4ID', jsonb_build_object(
    'email', 'alice@example.com',
    'name', 'Alice Johnson',
    'photo_url', 'https://example.com/alice.jpg',
    'username', 'alice-search-user'
));
select fx_user(:'user7ID', jsonb_build_object(
    'name', 'User Percent Test',
    'username', 'user%test'
));
select fx_user(:'user8ID', jsonb_build_object(
    'name', 'User Underscore',
    'username', 'user_special'
));
select fx_user(:'user9ID', jsonb_build_object(
    'name', 'Back Slash',
    'username', 'back\slash'
));
select fx_user(:'userPreRegisteredID', jsonb_build_object('registration_status', 'pre-registered'));
select fx_user(:'userUnverifiedID', jsonb_build_object(
    'email_verified', false,
    'username', 'unverified'
));

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
            'username', 'alice-search-user',
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
