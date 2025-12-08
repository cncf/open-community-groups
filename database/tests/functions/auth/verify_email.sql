-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    host,
    description,
    header_logo_url,
    theme,
    title
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'test.example.com',
    'Seattle community for cloud native technologies',
    'https://example.com/logo.png',
    '{}'::jsonb,
    'Cloud Native Seattle Community'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set email_verified to true for valid verification code

-- Create user with unverified email
with test_user as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'test1@example.com',
            'username', 'testuser1',
            'name', 'Test User 1'
        ),
        false
    )
)
-- Use the verification code
select verify_email(verification_code) from test_user;

-- Now check that email was verified
select is(
    email_verified,
    true,
    'Should set email_verified to true for valid verification code'
) from "user" 
where email = 'test1@example.com';

-- Should delete verification code after use
with test_user as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'test1b@example.com',
            'username', 'testuser1b',
            'name', 'Test User 1b'
        ),
        false
    )
),
verification_result as (
    select 
        verification_code,
        verify_email(verification_code) as verify_result
    from test_user
)
select is(
    count(*)::integer,
    0,
    'Should delete verification code after use'
) from email_verification_code 
where email_verification_code_id = (select verification_code from verification_result);

-- Should raise exception for invalid verification code
select throws_ok(
    'select verify_email(''00000000-0000-0000-0000-000000000099''::uuid)',
    'email verification failed: invalid code',
    'Should raise exception for non-existent verification code'
);

-- Should raise exception for expired verification code

-- Create user and expire their code
with test_user as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'test2@example.com',
            'username', 'testuser2',
            'name', 'Test User 2'
        ),
        false
    )
),
expired_code_update as (
    update email_verification_code
    set created_at = current_timestamp - interval '25 hours'
    where email_verification_code_id = (select verification_code from test_user)
    returning email_verification_code_id
)
select throws_ok(
    'select verify_email(''' || coalesce((select email_verification_code_id::text from expired_code_update), '00000000-0000-0000-0000-000000000098') || '''::uuid)',
    'email verification failed: invalid code',
    'Should raise exception for expired verification code'
);

-- Should raise exception for already used verification code
with test_user as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'test3@example.com',
            'username', 'testuser3',
            'name', 'Test User 3'
        ),
        false
    )
),
first_use as (
    select 
        verification_code,
        verify_email(verification_code) as verify_result
    from test_user
)
select throws_ok(
    format('select verify_email(''%s''::uuid)', (select verification_code from first_use)),
    'email verification failed: invalid code',
    'Should raise exception for already used verification code'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
