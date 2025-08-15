begin;

select plan(2);

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

insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    name,
    auth_hash,
    community_id
) values (
    '00000000-0000-0000-0001-000000000001'::uuid,
    'test@example.com',
    'testuser',
    true,
    'Test User',
    'test_hash'::bytea,
    '00000000-0000-0000-0000-000000000001'::uuid
);

-- Test: User found by ID
select is(
    get_user_by_id('00000000-0000-0000-0001-000000000001'::uuid)::jsonb,
    '{
        "email": "test@example.com",
        "email_verified": true,
        "name": "Test User",
        "user_id": "00000000-0000-0000-0001-000000000001",
        "username": "testuser"
    }'::jsonb,
    'Should return user when ID exists'
);

-- Test: User not found
select is(
    get_user_by_id('00000000-0000-0000-0001-999999999999'::uuid)::jsonb,
    null::jsonb,
    'Should return null when ID does not exist'
);

select * from finish();
rollback;