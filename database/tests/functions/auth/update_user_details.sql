-- Start transaction and plan tests
begin;
select plan(2);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000002'

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

-- Seed user
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    email_verified,
    name,
    username
) values (
    :'user1ID',
    gen_random_bytes(32),
    :'community1ID',
    'test@example.com',
    true,
    'Test User',
    'testuser'
);

-- Test: Update user with all fields
select update_user_details(
    :'user1ID'::uuid,
    jsonb_build_object(
        'email', 'updated@example.com',
        'name', 'Updated User',
        'username', 'updateduser',
        'bio', 'This is my bio',
        'city', 'San Francisco',
        'company', 'Example Corp',
        'country', 'USA',
        'facebook_url', 'https://facebook.com/updateduser',
        'interests', array['programming', 'music', 'sports'],
        'linkedin_url', 'https://linkedin.com/in/updateduser',
        'photo_url', 'https://example.com/photo.jpg',
        'timezone', 'America/Los_Angeles',
        'title', 'Software Engineer',
        'twitter_url', 'https://twitter.com/updateduser',
        'website_url', 'https://example.com/updateduser'
    )
);

select is(
    get_user_by_id(:'user1ID'::uuid)::jsonb,
    jsonb_build_object(
        'auth_hash', (select auth_hash from "user" where user_id = :'user1ID'::uuid),
        'email', 'updated@example.com',
        'email_verified', true,
        'name', 'Updated User',
        'user_id', :'user1ID'::text,
        'username', 'updateduser',
        'bio', 'This is my bio',
        'city', 'San Francisco',
        'company', 'Example Corp',
        'country', 'USA',
        'facebook_url', 'https://facebook.com/updateduser',
        'interests', array['programming', 'music', 'sports'],
        'linkedin_url', 'https://linkedin.com/in/updateduser',
        'photo_url', 'https://example.com/photo.jpg',
        'timezone', 'America/Los_Angeles',
        'title', 'Software Engineer',
        'twitter_url', 'https://twitter.com/updateduser',
        'website_url', 'https://example.com/updateduser'
    ),
    'Should update all user fields correctly'
);

-- Test: Update user with null optional fields
select update_user_details(
    :'user1ID'::uuid,
    jsonb_build_object(
        'email', 'final@example.com',
        'name', 'Final User',
        'username', 'finaluser',
        'bio', null,
        'city', null,
        'company', null,
        'country', null,
        'facebook_url', null,
        'interests', null,
        'linkedin_url', null,
        'photo_url', null,
        'timezone', null,
        'title', null,
        'twitter_url', null,
        'website_url', null
    )
);

select is(
    get_user_by_id(:'user1ID'::uuid)::jsonb,
    jsonb_build_object(
        'auth_hash', (select auth_hash from "user" where user_id = :'user1ID'::uuid),
        'email', 'final@example.com',
        'email_verified', true,
        'name', 'Final User',
        'user_id', :'user1ID'::text,
        'username', 'finaluser'
    ),
    'Should handle null values for optional fields correctly'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;