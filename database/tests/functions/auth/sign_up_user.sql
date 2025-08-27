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
        "username": "defaultuser"
    }'::jsonb)
    and ("user"::jsonb ? 'auth_hash')
    and length(("user"::jsonb->>'auth_hash')) = 64
    and verification_code is not null,
    'User without email_verified parameter should default to false and generate verification code'
) from default_user_result;

-- Duplicate username should get numeric suffix starting at 2
with duplicate_user_1 as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'duplicate1@example.com',
            'username', 'duplicateuser',
            'name', 'First Duplicate User',
            'password', 'hashedpassword111'
        ),
        true
    )
),
duplicate_user_2 as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'duplicate2@example.com',
            'username', 'duplicateuser',
            'name', 'Second Duplicate User',
            'password', 'hashedpassword222'
        ),
        true
    )
)
select ok(
    (select "user"::jsonb->>'username' from duplicate_user_1) = 'duplicateuser'
    and (select "user"::jsonb->>'username' from duplicate_user_2) = 'duplicateuser2',
    'Duplicate username should get numeric suffix starting at 2'
);

-- Multiple duplicate usernames should increment properly
with duplicate_user_3 as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'duplicate3@example.com',
            'username', 'duplicateuser',
            'name', 'Third Duplicate User',
            'password', 'hashedpassword333'
        ),
        true
    )
),
duplicate_user_4 as (
    select * from sign_up_user(
        :'communityID',
        jsonb_build_object(
            'email', 'duplicate4@example.com',
            'username', 'duplicateuser',
            'name', 'Fourth Duplicate User',
            'password', 'hashedpassword444'
        ),
        true
    )
)
select ok(
    (select "user"::jsonb->>'username' from duplicate_user_3) = 'duplicateuser3'
    and (select "user"::jsonb->>'username' from duplicate_user_4) = 'duplicateuser4',
    'Multiple duplicate usernames should increment properly (3, 4, etc)'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
