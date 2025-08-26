-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community (required for user registration)
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

-- User with email_verified=true should not generate verification code
with verified_user_result as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'verified@example.com',
            'username', 'verifieduser',
            'name', 'Verified User',
            'password', 'hashedpassword123'
        ),
        true
    )
)
select ok(
    ("user"::jsonb - 'user_id'::text - 'auth_hash'::text = '{
        "email": "verified@example.com",
        "email_verified": true,
        "name": "Verified User",
        "password": "hashedpassword123",
        "username": "verifieduser"
    }'::jsonb)
    and ("user"::jsonb ? 'auth_hash')
    and length(("user"::jsonb->>'auth_hash')) = 64
    and verification_code is null,
    'User with email_verified=true should not generate verification code'
) from verified_user_result;

-- User with email_verified=false should generate verification code
with unverified_user_result as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'unverified@example.com',
            'username', 'unverifieduser',
            'name', 'Unverified User',
            'password', 'hashedpassword456'
        ),
        false
    )
)
select ok(
    ("user"::jsonb - 'user_id'::text - 'auth_hash'::text = '{
        "email": "unverified@example.com",
        "email_verified": false,
        "name": "Unverified User",
        "password": "hashedpassword456",
        "username": "unverifieduser"
    }'::jsonb)
    and ("user"::jsonb ? 'auth_hash')
    and length(("user"::jsonb->>'auth_hash')) = 64
    and verification_code is not null,
    'User with email_verified=false should generate verification code'
) from unverified_user_result;

-- User without email_verified parameter defaults to false and generates code
with default_user_result as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'default@example.com',
            'username', 'defaultuser',
            'name', 'Default User',
            'password', 'hashedpassword789'
        )
    )
)
select ok(
    ("user"::jsonb - 'user_id'::text - 'auth_hash'::text = '{
        "email": "default@example.com",
        "email_verified": false,
        "name": "Default User",
        "password": "hashedpassword789",
        "username": "defaultuser"
    }'::jsonb)
    and ("user"::jsonb ? 'auth_hash')
    and length(("user"::jsonb->>'auth_hash')) = 64
    and verification_code is not null,
    'User without email_verified parameter should default to false and generate verification code'
) from default_user_result;

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
