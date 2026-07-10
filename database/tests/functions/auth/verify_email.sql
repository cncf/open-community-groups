-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set invalidVerificationCodeID '0a0f0000-0000-0000-0000-000000000001'
\set expiredUserID '0a0f0000-0000-0000-0000-000000000002'
\set expiredVerificationCodeID '0a0f0000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User with an expired email verification code
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (
    :'expiredUserID',
    'expired-verification-code-hash',
    'test2@example.com',
    false,
    'testuser2'
);

insert into email_verification_code (email_verification_code_id, created_at, user_id)
values (
    :'expiredVerificationCodeID',
    current_timestamp - interval '25 hours',
    :'expiredUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set email_verified to true for valid verification code
with test_user as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'test1@example.com',
            'username', 'testuser1',
            'name', 'Test User 1'
        ),
        false,
        gen_random_uuid(),
        '{}'::jsonb
    )
)

select lives_ok(
    format('select verify_email(%L::uuid)', verification_code),
    'Should verify email for valid verification code'
)
from test_user;

select is(
    (
        select email_verified
        from "user"
        where email = 'test1@example.com'
    ),
    true,
    'Should set email_verified to true for valid verification code'
);

-- Should delete verification code after use
with test_user as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'test1b@example.com',
            'username', 'testuser1b',
            'name', 'Test User 1b'
        ),
        false,
        gen_random_uuid(),
        '{}'::jsonb
    )
)

select verification_code as "verificationCodeToDelete"
from test_user \gset

select lives_ok(
    format('select verify_email(%L::uuid)', :'verificationCodeToDelete'),
    'Should verify email for a code that is deleted after use'
);

select is(
    count(*)::integer,
    0,
    'Should delete verification code after use'
) from email_verification_code
where email_verification_code_id = :'verificationCodeToDelete'::uuid;

-- Should raise exception for invalid verification code
select throws_ok(
    format('select verify_email(%L::uuid)', :'invalidVerificationCodeID'),
    'email verification failed: invalid code',
    'Should raise exception for non-existent verification code'
);

-- Should raise exception for expired verification code
select throws_ok(
    format('select verify_email(%L::uuid)', :'expiredVerificationCodeID'),
    'email verification failed: invalid code',
    'Should raise exception for expired verification code'
);

-- Should raise exception for already used verification code
with test_user as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'test3@example.com',
            'username', 'testuser3',
            'name', 'Test User 3'
        ),
        false,
        gen_random_uuid(),
        '{}'::jsonb
    )
)

select verification_code as "usedVerificationCode"
from test_user \gset

select lives_ok(
    format('select verify_email(%L::uuid)', :'usedVerificationCode'),
    'Should verify email on first use of the verification code'
);

select throws_ok(
    format('select verify_email(%L::uuid)', :'usedVerificationCode'),
    'email verification failed: invalid code',
    'Should raise exception for already used verification code'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
