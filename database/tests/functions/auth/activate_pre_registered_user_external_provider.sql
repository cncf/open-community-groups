-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set registeredUserID '0a020000-0000-0000-0000-000000000001'
\set takenUsernameUserID '0a020000-0000-0000-0000-000000000002'
\set unknownUserID '0a020000-0000-0000-0000-000000000003'
\set userID '0a020000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Pre-registered user activated by external provider
select fx_user(:'userID', jsonb_build_object(
    'auth_hash', 'pre-registered-hash',
    'email_verified', false,
    'registration_status', 'pre-registered'
));

-- Registered user that cannot be activated again
select fx_user(:'registeredUserID');

-- Existing username collision for activation
select fx_user(:'takenUsernameUserID', jsonb_build_object('username', 'alice-external-provider'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should activate a pre-registered user and resolve username collisions.
select is(
    activate_pre_registered_user_external_provider(
        :'userID',
        '{
            "name": "Alice Invited",
            "provider": {"lf": {"sub": "123"}},
            "username": "alice-external-provider"
        }'::jsonb
    )::jsonb->>'username',
    'alice-external-provider2',
    'Should return the activated user with a unique username'
);

-- Should promote the placeholder row into a verified registered user.
select results_eq(
    format($$
        select
            email_verified,
            name,
            provider,
            registration_status,
            username
        from "user"
        where user_id = %L::uuid
    $$, :'userID'),
    $$
        values (
            true,
            'Alice Invited',
            '{"lf": {"sub": "123"}}'::jsonb,
            'registered',
            'alice-external-provider2'
        )
    $$,
    'Should promote the placeholder row into a verified registered user'
);

-- Should rotate the user's auth hash during activation.
select ok(
    (
        select auth_hash <> 'pre-registered-hash'
        from "user"
        where user_id = :'userID'::uuid
    ),
    'Should rotate the user auth hash during activation'
);

-- Should reject users that are already registered.
select throws_ok(
    format($$ select activate_pre_registered_user_external_provider(
        %L::uuid,
        '{"name": "Registered User", "provider": {}, "username": "registered-user"}'::jsonb
    ) $$, :'registeredUserID'),
    'OCG01',
    'pre-registered user not found',
    'Should reject users that are already registered'
);

-- Should reject missing pre-registered users.
select throws_ok(
    format($$ select activate_pre_registered_user_external_provider(
        %L::uuid,
        '{"name": "Missing User", "provider": {}, "username": "missing"}'::jsonb
    ) $$, :'unknownUserID'),
    'OCG01',
    'pre-registered user not found',
    'Should reject missing pre-registered users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
