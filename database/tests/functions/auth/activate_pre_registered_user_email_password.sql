-- Tests activating pre-registered users after email/password signup.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set newVerificationCodeID '0a010000-0000-0000-0000-000000000005'
\set nullCodePreRegisteredUserID '0a010000-0000-0000-0000-000000000006'
\set nullCodeRegisteredUserID '0a010000-0000-0000-0000-000000000007'
\set registeredUserID '0a010000-0000-0000-0000-000000000001'
\set takenUsernameUserID '0a010000-0000-0000-0000-000000000002'
\set userID '0a010000-0000-0000-0000-000000000003'
\set verificationCodeID '0a010000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Pre-registered user activated by email/password signup
select fx_user(:'userID', jsonb_build_object(
    'auth_hash', 'pre-registered-hash',
    'email', 'invited@example.com',
    'email_verified', false,
    'registration_status', 'pre-registered'
));

-- Pre-registered user whose activation is rejected without a verification code
select fx_user(:'nullCodePreRegisteredUserID', jsonb_build_object(
    'email', 'activation-null-code-invited@example.com',
    'email_verified', false,
    'registration_status', 'pre-registered'
));

-- Registered user that returns no rows when activated without a verification code
select fx_user(:'nullCodeRegisteredUserID', jsonb_build_object(
    'email', 'activation-null-code-registered@example.com'
));

-- Registered user that cannot be activated again
select fx_user(:'registeredUserID', jsonb_build_object('email', 'registered@example.com'));

-- Existing username collision for activation
select fx_user(:'takenUsernameUserID', jsonb_build_object('username', 'alice'));

-- Existing verification code to rotate on activation
insert into email_verification_code (email_verification_code_id, user_id, created_at)
values (:'verificationCodeID', :'userID', '2024-01-01 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Activate the pre-registered user
select to_jsonb(activated) as "activation"
from activate_pre_registered_user_email_password(
    '{
        "email": "INVITED@example.com",
        "name": "Alice Invited",
        "password": "hashed-password",
        "username": "alice"
    }'::jsonb,
    :'newVerificationCodeID',
    jsonb_build_object(
        'link', 'https://example.test/verify-email/' || :'newVerificationCodeID',
        'theme', jsonb_build_object('primary_color', '#123456')
    )
) as activated \gset

-- Should return the activated user projection with a unique username
select is(
    (:'activation'::jsonb->'user') - 'auth_hash',
    jsonb_build_object(
        'email', 'invited@example.com',
        'email_verified', false,
        'name', 'Alice Invited',
        'user_id', :'userID',
        'username', 'alice2',

        'has_password', true,

        'belongs_to_any_group_team', false,
        'belongs_to_community_team', false
    ),
    'Should return the activated user projection with a unique username'
);

-- Should return the caller-provided verification code
select is(
    (:'activation'::jsonb->>'verification_code')::uuid,
    :'newVerificationCodeID'::uuid,
    'Should return the caller-provided verification code'
);

-- Should promote the placeholder row into an unverified registered user with password
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

-- Should rotate the user auth hash during activation
select ok(
    (
        select auth_hash <> 'pre-registered-hash'
        from "user"
        where user_id = :'userID'::uuid
    ),
    'Should rotate the user auth hash during activation'
);

-- Should rotate the existing email verification code to the caller-provided code
select results_eq(
    format(
        $$
            select email_verification_code_id
            from email_verification_code
            where user_id = %L::uuid
        $$,
        :'userID'
    ),
    format($$values (%L::uuid)$$, :'newVerificationCodeID'),
    'Should rotate the existing email verification code to the caller-provided code'
);

-- Should reject activation without a verification code
select throws_ok(
    $$
        select * from activate_pre_registered_user_email_password(
            '{
                "email": "activation-null-code-invited@example.com",
                "name": "Null Code Invited",
                "password": "new-password",
                "username": "activation-null-code-invited"
            }'::jsonb,
            null::uuid,
            '{}'::jsonb
        )
    $$,
    'P0001',
    'verification code is required to send verification email',
    'Should reject activation without a verification code'
);

-- Should keep the placeholder pre-registered when activation is rejected
select is(
    (
        select registration_status
        from "user"
        where user_id = :'nullCodePreRegisteredUserID'::uuid
    ),
    'pre-registered',
    'Should keep the placeholder pre-registered when activation is rejected'
);

-- Should return null when the email belongs to an already registered user
select is(
    (
        select "user"::jsonb
        from activate_pre_registered_user_email_password(
            '{
                "email": "registered@example.com",
                "name": "Registered User",
                "password": "new-password",
                "username": "registered-user"
            }'::jsonb,
            gen_random_uuid(),
            '{}'::jsonb
        )
    ),
    null::jsonb,
    'Should return null when the email belongs to an already registered user'
);

-- Should return null when the email does not exist
select is(
    (
        select "user"::jsonb
        from activate_pre_registered_user_email_password(
            '{
                "email": "missing@example.com",
                "name": "Missing User",
                "password": "new-password",
                "username": "missing-user"
            }'::jsonb,
            gen_random_uuid(),
            '{}'::jsonb
        )
    ),
    null::jsonb,
    'Should return null when the email does not exist'
);

-- Should return no rows without a verification code when the email is not pre-registered
select is_empty(
    $$
        select * from activate_pre_registered_user_email_password(
            '{
                "email": "activation-null-code-registered@example.com",
                "name": "Null Code Registered",
                "password": "new-password",
                "username": "activation-null-code-registered"
            }'::jsonb,
            null::uuid,
            '{}'::jsonb
        )
    $$,
    'Should return no rows without a verification code when the email is not pre-registered'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
