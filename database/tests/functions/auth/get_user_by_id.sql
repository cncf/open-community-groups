begin;

select plan(4);

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
    community_id,
    password
) values (
    '00000000-0000-0000-0001-000000000001'::uuid,
    'test@example.com',
    'testuser',
    true,
    'Test User',
    'test_hash'::bytea,
    '00000000-0000-0000-0000-000000000001'::uuid,
    'hashed_password_here'
);

-- Test: User found by ID (without password)
select is(
    get_user_by_id('00000000-0000-0000-0001-000000000001'::uuid, false)::jsonb,
    '{
        "auth_hash": "\\x746573745f68617368",
        "email": "test@example.com",
        "email_verified": true,
        "has_password": true,
        "name": "Test User",
        "user_id": "00000000-0000-0000-0001-000000000001",
        "username": "testuser"
    }'::jsonb,
    'Should return user without password when include_password is false'
);

-- Test: User found by ID (with password)
select is(
    get_user_by_id('00000000-0000-0000-0001-000000000001'::uuid, true)::jsonb,
    '{
        "auth_hash": "\\x746573745f68617368",
        "email": "test@example.com",
        "email_verified": true,
        "has_password": true,
        "name": "Test User",
        "password": "hashed_password_here",
        "user_id": "00000000-0000-0000-0001-000000000001",
        "username": "testuser"
    }'::jsonb,
    'Should return user with password when include_password is true'
);

-- Test: User found by ID (default parameter - no password)
select is(
    get_user_by_id('00000000-0000-0000-0001-000000000001'::uuid)::jsonb,
    '{
        "auth_hash": "\\x746573745f68617368",
        "email": "test@example.com",
        "email_verified": true,
        "has_password": true,
        "name": "Test User",
        "user_id": "00000000-0000-0000-0001-000000000001",
        "username": "testuser"
    }'::jsonb,
    'Should return user without password when using default parameter'
);

-- Test: User not found
select is(
    get_user_by_id('00000000-0000-0000-0001-999999999999'::uuid)::jsonb,
    null::jsonb,
    'Should return null when ID does not exist'
);

select * from finish();
rollback;