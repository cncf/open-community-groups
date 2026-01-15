-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set user2ID '00000000-0000-0000-0000-000000000003'
\set user3ID '00000000-0000-0000-0000-000000000004'
\set userID '00000000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User for updates
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    name,
    username
) values (
    :'userID',
    gen_random_bytes(32),
    'test@example.com',
    true,
    'Original User',
    'testuser'
);

-- User with optional fields
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    name,
    username,
    bio,
    city,
    company,
    country,
    facebook_url,
    interests,
    linkedin_url,
    photo_url,
    timezone,
    title,
    twitter_url,
    website_url
) values (
    :'user2ID',
    gen_random_bytes(32),
    'test2@example.com',
    true,
    'Second User',
    'testuser2',
    'Original bio',
    'Seattle',
    'Original Company',
    'USA',
    'https://facebook.com/original',
    array['reading', 'gaming'],
    'https://linkedin.com/in/original',
    'https://example.com/original.jpg',
    'America/Los_Angeles',
    'Original Title',
    'https://twitter.com/original',
    'https://example.com/original'
);

-- User for explicit null test
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    name,
    username,
    bio,
    city,
    company,
    country,
    facebook_url,
    interests,
    linkedin_url,
    photo_url,
    timezone,
    title,
    twitter_url,
    website_url
) values (
    :'user3ID',
    gen_random_bytes(32),
    'test3@example.com',
    true,
    'Third User',
    'testuser3',
    'Third user bio',
    'Portland',
    'Third Company',
    'Canada',
    'https://facebook.com/third',
    array['cooking', 'travel'],
    'https://linkedin.com/in/third',
    'https://example.com/third.jpg',
    'America/New_York',
    'Third Title',
    'https://twitter.com/third',
    'https://example.com/third'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Update user with all updateable fields
select update_user_details(
    :'userID'::uuid,
    '{
        "name": "Updated User",
        "bio": "This is my bio",
        "city": "San Francisco",
        "company": "Example Corp",
        "country": "USA",
        "facebook_url": "https://facebook.com/updateduser",
        "interests": ["programming", "music", "sports"],
        "linkedin_url": "https://linkedin.com/in/updateduser",
        "photo_url": "https://example.com/photo.jpg",
        "timezone": "America/Los_Angeles",
        "title": "Software Engineer",
        "twitter_url": "https://twitter.com/updateduser",
        "website_url": "https://example.com/updateduser"
    }'::jsonb
);

-- Should update all provided user fields
select is(
    get_user_by_id(:'userID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', (select auth_hash from "user" where user_id = :'userID'::uuid),
        'user_id', :'userID'::text
    ) || '{
        "belongs_to_any_group_team": false,
        "belongs_to_community_team": false,
        "email": "test@example.com",
        "email_verified": true,
        "name": "Updated User",
        "username": "testuser",
        "bio": "This is my bio",
        "city": "San Francisco",
        "company": "Example Corp",
        "country": "USA",
        "facebook_url": "https://facebook.com/updateduser",
        "interests": ["programming", "music", "sports"],
        "linkedin_url": "https://linkedin.com/in/updateduser",
        "photo_url": "https://example.com/photo.jpg",
        "timezone": "America/Los_Angeles",
        "title": "Software Engineer",
        "twitter_url": "https://twitter.com/updateduser",
        "website_url": "https://example.com/updateduser"
    }'::jsonb,
    'Should update all provided user fields'
);

-- Update user with only required field (name), rest are null
select update_user_details(
    :'user2ID'::uuid,
    '{
        "name": "Updated Name Only"
    }'::jsonb
);

-- Should clear optional fields when only name is provided
select is(
    get_user_by_id(:'user2ID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', (select auth_hash from "user" where user_id = :'user2ID'::uuid),
        'user_id', :'user2ID'::text
    ) || '{
        "belongs_to_any_group_team": false,
        "belongs_to_community_team": false,
        "email": "test2@example.com",
        "email_verified": true,
        "name": "Updated Name Only",
        "username": "testuser2"
    }'::jsonb,
    'Should clear optional fields when only name is provided'
);

-- Update user with required field and explicit null values for optional fields
select update_user_details(
    :'user3ID'::uuid,
    '{
        "name": "Explicitly Nulled User",
        "bio": null,
        "city": null,
        "company": null,
        "country": null,
        "facebook_url": null,
        "interests": null,
        "linkedin_url": null,
        "photo_url": null,
        "timezone": null,
        "title": null,
        "twitter_url": null,
        "website_url": null
    }'::jsonb
);

-- Should handle explicit null values same as omitted fields
select is(
    get_user_by_id(:'user3ID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', (select auth_hash from "user" where user_id = :'user3ID'::uuid),
        'user_id', :'user3ID'::text
    ) || '{
        "belongs_to_any_group_team": false,
        "belongs_to_community_team": false,
        "email": "test3@example.com",
        "email_verified": true,
        "name": "Explicitly Nulled User",
        "username": "testuser3"
    }'::jsonb,
    'Should handle explicit null values same as omitted fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
