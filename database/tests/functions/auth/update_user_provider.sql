-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set nullProviderUserID '0a0c0000-0000-0000-0000-000000000001'
\set userID '0a0c0000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    provider,
    username
) values (
    :'nullProviderUserID',
    'null-provider-hash',
    'null-provider@example.com',
    true,
    null,
    'null-provider-user'
), (
    :'userID',
    'test-hash',
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
    format(
        $$
        select update_user_provider(
            %L::uuid,
            jsonb_build_object(
                'github', jsonb_build_object(
                    'username', 'octocat-renamed'
                )
            )
        )
        $$,
        :'userID'
    ),
    'Should refresh existing provider metadata for the same provider'
);

-- Should merge provider metadata across different providers
select lives_ok(
    format(
        $$
        select update_user_provider(
            %L::uuid,
            jsonb_build_object(
                'linuxfoundation', jsonb_build_object(
                    'username', 'lf-user'
                )
            )
        )
        $$,
        :'userID'
    ),
    'Should merge provider metadata across different providers'
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

-- Should initialize null provider payloads before merging
select lives_ok(
    format(
        $$
        select update_user_provider(
            %L::uuid,
            jsonb_build_object(
                'github', jsonb_build_object(
                    'username', 'new-octocat'
                )
            )
        )
        $$,
        :'nullProviderUserID'
    ),
    'Should merge provider metadata when existing provider is null'
);

select is(
    (select provider from "user" where user_id = :'nullProviderUserID'::uuid),
    jsonb_build_object(
        'github', jsonb_build_object(
            'username', 'new-octocat'
        )
    ),
    'Should store provider metadata when existing provider is null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
