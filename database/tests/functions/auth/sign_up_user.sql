-- Start transaction and plan tests
begin;
select plan(3);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'

-- Seed community
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
    :'community1ID',
    'Test Community',
    'Test Community',
    'test.example.com',
    'Test Community Description',
    'https://example.com/logo.png',
    '{}'::jsonb,
    'Test Community Title'
);

-- Test: Create user with email_verified=true (should NOT generate verification code)
with verified_user_result as (
    select * from sign_up_user(
        :'community1ID',
        jsonb_build_object(
            'email', 'verified@example.com',
            'username', 'verifieduser',
            'name', 'Verified User',
            'email_verified', true
        )
    )
)
select ok(
    "user"::jsonb - 'user_id'::text = '{
        "email": "verified@example.com",
        "email_verified": true,
        "name": "Verified User",
        "username": "verifieduser"
    }'::jsonb
    and verification_code is null,
    'User with email_verified=true should not generate verification code'
) from verified_user_result;

-- Test: Create user with email_verified=false (should generate verification code)
with unverified_user_result as (
    select * from sign_up_user(
        :'community1ID',
        jsonb_build_object(
            'email', 'unverified@example.com',
            'username', 'unverifieduser',
            'name', 'Unverified User',
            'email_verified', false
        )
    )
)
select ok(
    "user"::jsonb - 'user_id'::text = '{
        "email": "unverified@example.com",
        "email_verified": false,
        "name": "Unverified User",
        "username": "unverifieduser"
    }'::jsonb
    and verification_code is not null,
    'User with email_verified=false should generate verification code'
) from unverified_user_result;

-- Test: Create user without email_verified field (should default to false and generate code)
with default_user_result as (
    select * from sign_up_user(
        :'community1ID',
        jsonb_build_object(
            'email', 'default@example.com',
            'username', 'defaultuser',
            'name', 'Default User'
        )
    )
)
select ok(
    "user"::jsonb - 'user_id'::text = '{
        "email": "default@example.com",
        "email_verified": false,
        "name": "Default User",
        "username": "defaultuser"
    }'::jsonb
    and verification_code is not null,
    'User without email_verified should default to false and generate verification code'
) from default_user_result;

-- Finish tests and rollback transaction
select * from finish();
rollback;