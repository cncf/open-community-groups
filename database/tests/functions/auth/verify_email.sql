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

-- Valid verification code should verify email

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
    'Valid verification code should set email_verified to true'
) from "user" 
where email = 'test1@example.com';

-- Verification code should be deleted after use
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
    'Verification code should be deleted after use'
) from email_verification_code 
where email_verification_code_id = (select verification_code from verification_result);

-- Invalid verification code raises exception
select throws_ok(
    'select verify_email(''00000000-0000-0000-0000-000000000099''::uuid)',
    'P0001',
    'invalid email verification code',
    'Non-existent verification code should raise exception'
);

-- Expired verification code raises exception

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
    'P0001',
    'invalid email verification code',
    'Expired verification code should raise exception'
);

-- Already used verification code raises exception
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
    'P0001',
    'invalid email verification code',
    'Already used verification code should raise exception'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
