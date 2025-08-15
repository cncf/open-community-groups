begin;

select plan(1);

-- Create test data
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
    '00000000-0000-0000-0000-000000000001'::uuid,
    'Test Community',
    'Test Community',
    'test.example.com',
    'Test Community Description',
    'https://example.com/logo.png',
    '{}'::jsonb,
    'Test Community Title'
);

-- Test: Create new user - check structure and fields except user_id
with new_user_result as (
    select sign_up_user(
        '00000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_object(
            'email', 'newuser@example.com',
            'username', 'newuser',
            'name', 'New User',
            'email_verified', true
        )
    )::jsonb as result
)
select is(
    result - 'user_id'::text,
    '{
        "email": "newuser@example.com",
        "email_verified": true,
        "name": "New User",
        "username": "newuser"
    }'::jsonb,
    'Should create new user and return correct structure'
) from new_user_result;

select * from finish();
rollback;