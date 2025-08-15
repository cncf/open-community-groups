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

-- Create a test user
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    email_verified,
    name,
    username
) values (
    '00000000-0000-0000-0000-000000000002'::uuid,
    gen_random_bytes(32),
    '00000000-0000-0000-0000-000000000001'::uuid,
    'test@example.com',
    true,
    'Test User',
    'testuser'
);

-- Test: Update user with all fields
select update_user_details(
    jsonb_build_object(
        'user_id', '00000000-0000-0000-0000-000000000002',
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
    jsonb_build_object(
        'email', email,
        'name', name,
        'username', username,
        'bio', bio,
        'city', city,
        'company', company,
        'country', country,
        'facebook_url', facebook_url,
        'interests', interests,
        'linkedin_url', linkedin_url,
        'photo_url', photo_url,
        'timezone', timezone,
        'title', title,
        'twitter_url', twitter_url,
        'website_url', website_url
    ),
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
    ),
    'Should update all user fields correctly'
) from "user" where user_id = '00000000-0000-0000-0000-000000000002'::uuid;

-- Test: Update user with null optional fields
select update_user_details(
    jsonb_build_object(
        'user_id', '00000000-0000-0000-0000-000000000002',
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
    jsonb_build_object(
        'email', email,
        'name', name,
        'username', username,
        'bio', bio,
        'city', city,
        'company', company,
        'country', country,
        'facebook_url', facebook_url,
        'interests', interests,
        'linkedin_url', linkedin_url,
        'photo_url', photo_url,
        'timezone', timezone,
        'title', title,
        'twitter_url', twitter_url,
        'website_url', website_url
    ),
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
    ),
    'Should handle null values for optional fields correctly'
) from "user" where user_id = '00000000-0000-0000-0000-000000000002'::uuid;

select * from finish();
rollback;