-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userID '00000000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    provider,
    username
) values (
    :'userID',
    'test_hash',
    'user@example.com',
    true,
    jsonb_build_object(
        'github', jsonb_build_object(
            'username', 'octocat'
        )
    ),
    'test-user'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should replace the provider payload for the same provider key
select lives_ok(
    $$
        select update_user_provider(
            '00000000-0000-0000-0000-000000000011'::uuid,
            jsonb_build_object(
                'github', jsonb_build_object(
                    'username', 'octocat-renamed'
                )
            )
        )
    $$,
    'Should refresh existing provider metadata for the same provider'
);

-- Should merge provider metadata across different providers
select update_user_provider(
    :'userID'::uuid,
    jsonb_build_object(
        'linuxfoundation', jsonb_build_object(
            'username', 'lf-user'
        )
    )
);

select is(
    (select provider from "user" where user_id = :'userID'::uuid),
    jsonb_build_object(
        'github', jsonb_build_object(
            'username', 'octocat-renamed'
        ),
        'linuxfoundation', jsonb_build_object(
            'username', 'lf-user'
        )
    ),
    'Should preserve other provider keys when merging provider metadata'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
