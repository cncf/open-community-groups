-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

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
    password,
    registration_status,
    user_id,
    username
) values
    ('pre-registered-hash', 'invited@example.com', false, null, null, 'pre-registered', :'userID', 'invited-user'),
    ('registered-hash', 'registered@example.com', false, 'Registered User', 'secret', 'registered', :'registeredUserID', 'registered-user'),
    ('taken-hash', 'taken@example.com', true, 'Taken User', 'secret', 'registered', :'takenUsernameUserID', 'alice');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should activate a pre-registered user and resolve username collisions.
select is(
    (
        select "user"::jsonb->>'username'
        from activate_pre_registered_user_email_password(
            '{
                "email": "INVITED@example.com",
                "name": "Alice Invited",
                "password": "hashed-password",
                "username": "alice"
            }'::jsonb
        )
    ),
    'alice2',
    'Should return the activated user with a unique username'
);

-- Should promote the placeholder row into an unverified registered user with password.
select results_eq(
    $$
        select
            email_verified,
            name,
            password,
            registration_status,
            username
        from "user"
        where user_id = '00000000-0000-0000-0000-000000000101'::uuid
    $$,
    $$
        values (
            false,
            'Alice Invited',
            'hashed-password',
            'registered',
            'alice2'
        )
    $$,
    'Should promote the placeholder row into an unverified registered user with password'
);

-- Should create an email verification code for the activated user.
select is(
    (
        select count(*)
        from email_verification_code
        where user_id = :'userID'
    ),
    1::bigint,
    'Should create an email verification code for the activated user'
);

-- Should return null when the email belongs to an already registered user.
select is(
    (
        select "user"::jsonb
        from activate_pre_registered_user_email_password(
            '{
                "email": "registered@example.com",
                "name": "Registered User",
                "password": "new-password",
                "username": "registered-user"
            }'::jsonb
        )
    ),
    null::jsonb,
    'Should return null when the email belongs to an already registered user'
);

-- Should return null when the email does not exist.
select is(
    (
        select "user"::jsonb
        from activate_pre_registered_user_email_password(
            '{
                "email": "missing@example.com",
                "name": "Missing User",
                "password": "new-password",
                "username": "missing-user"
            }'::jsonb
        )
    ),
    null::jsonb,
    'Should return null when the email does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
