-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

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
        false
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
        false
    )
)

select verification_code as "verificationCodeToDelete"
from test_user \gset

select verify_email(:'verificationCodeToDelete'::uuid);

select is(
    count(*)::integer,
    0,
    'Should delete verification code after use'
) from email_verification_code
where email_verification_code_id = :'verificationCodeToDelete'::uuid;

-- Should raise exception for invalid verification code
select throws_ok(
    'select verify_email(''00000000-0000-0000-0000-000000000099''::uuid)',
    'email verification failed: invalid code',
    'Should raise exception for non-existent verification code'
);

-- Should raise exception for expired verification code
with test_user as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'test2@example.com',
            'username', 'testuser2',
            'name', 'Test User 2'
        ),
        false
    )
)

select verification_code as "expiredVerificationCode"
from test_user \gset

update email_verification_code
set created_at = current_timestamp - interval '25 hours'
where email_verification_code_id = :'expiredVerificationCode'::uuid;

select throws_ok(
    format('select verify_email(''%s''::uuid)', :'expiredVerificationCode'),
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
        false
    )
)

select verification_code as "usedVerificationCode"
from test_user \gset

select verify_email(:'usedVerificationCode'::uuid);

select throws_ok(
    format('select verify_email(''%s''::uuid)', :'usedVerificationCode'),
    'email verification failed: invalid code',
    'Should raise exception for already used verification code'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
