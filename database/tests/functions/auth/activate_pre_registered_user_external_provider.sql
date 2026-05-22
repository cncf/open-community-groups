-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set registeredUserID '00000000-0000-0000-0000-000000000102'
\set takenUsernameUserID '00000000-0000-0000-0000-000000000103'
\set userID '00000000-0000-0000-0000-000000000101'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    auth_hash,
    email,
    email_verified,
    name,
    registration_status,
    user_id,
    username
) values
    ('pre-registered-hash', 'invited@example.com', false, null, 'pre-registered', :'userID', 'invited-user'),
    ('registered-hash', 'registered@example.com', true, 'Registered User', 'registered', :'registeredUserID', 'registered-user'),
    ('taken-hash', 'taken@example.com', true, 'Taken User', 'registered', :'takenUsernameUserID', 'alice');

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
            "username": "alice"
        }'::jsonb
    )::jsonb->>'username',
    'alice2',
    'Should return the activated user with a unique username'
);

-- Should promote the placeholder row into a verified registered user.
select results_eq(
    $$
        select
            email_verified,
            name,
            provider,
            registration_status,
            username
        from "user"
        where user_id = '00000000-0000-0000-0000-000000000101'::uuid
    $$,
    $$
        values (
            true,
            'Alice Invited',
            '{"lf": {"sub": "123"}}'::jsonb,
            'registered',
            'alice2'
        )
    $$,
    'Should promote the placeholder row into a verified registered user'
);

-- Should reject users that are already registered.
select throws_ok(
    $$ select activate_pre_registered_user_external_provider(
        '00000000-0000-0000-0000-000000000102'::uuid,
        '{"name": "Registered User", "provider": {}, "username": "registered-user"}'::jsonb
    ) $$,
    'pre-registered user not found',
    'Should reject users that are already registered'
);

-- Should reject missing pre-registered users.
select throws_ok(
    $$ select activate_pre_registered_user_external_provider(
        '00000000-0000-0000-0000-999999999999'::uuid,
        '{"name": "Missing User", "provider": {}, "username": "missing"}'::jsonb
    ) $$,
    'pre-registered user not found',
    'Should reject missing pre-registered users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
