-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set registeredUserID '0a010000-0000-0000-0000-000000000001'
\set takenUsernameUserID '0a010000-0000-0000-0000-000000000002'
\set userID '0a010000-0000-0000-0000-000000000003'
\set verificationCodeID '0a010000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    user_id,
    name,
    auth_hash,
    email,
    email_verified,
    password,
    registration_status,
    username
) values (
    :'userID',
    null,
    'pre-registered-hash',
    'invited@example.com',
    false,
    null,
    'pre-registered',
    'invited-user'
), (
    :'registeredUserID',
    'Registered User',
    'registered-hash',
    'registered@example.com',
    false,
    'secret',
    'registered',
    'registered-user'
), (
    :'takenUsernameUserID',
    'Taken User',
    'taken-hash',
    'taken@example.com',
    true,
    'secret',
    'registered',
    'alice'
);

-- Existing verification code to refresh on activation
insert into email_verification_code (email_verification_code_id, user_id, created_at)
values (:'verificationCodeID', :'userID', '2024-01-01 00:00:00+00');

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
    format($$
        select
            email_verified,
            name,
            password,
            registration_status,
            username
        from "user"
        where user_id = %L::uuid
    $$, :'userID'),
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

-- Should rotate the user's auth hash during activation.
select ok(
    (
        select auth_hash <> 'pre-registered-hash'
        from "user"
        where user_id = :'userID'::uuid
    ),
    'Should rotate the user auth hash during activation'
);

-- Should keep one email verification code for the activated user.
select is(
    (
        select count(*)
        from email_verification_code
        where user_id = :'userID'
    ),
    1::bigint,
    'Should keep one email verification code for the activated user'
);

-- Should refresh the existing email verification code timestamp.
select ok(
    (
        select created_at > '2024-01-01 00:00:00+00'::timestamptz
        from email_verification_code
        where user_id = :'userID'::uuid
    ),
    'Should refresh the existing email verification code timestamp'
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
