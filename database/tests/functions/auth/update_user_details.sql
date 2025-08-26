-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set userID '00000000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community (required for user operations)
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

-- Test user for profile updates
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    email_verified,
    name,
    username
) values (
    :'userID',
    gen_random_bytes(32),
    :'communityID',
    'test@example.com',
    true,
    'Original User',
    'testuser'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Update user with all updateable fields
select update_user_details(
    :'userID'::uuid,
    jsonb_build_object(
        'name', 'Updated User',
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
    get_user_by_id(:'userID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', (select auth_hash from "user" where user_id = :'userID'::uuid),
        'belongs_to_any_group_team', false,
        'belongs_to_community_team', false,
        'email', 'test@example.com',
        'email_verified', true,
        'name', 'Updated User',
        'user_id', :'userID'::text,
        'username', 'testuser',
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
    'Should update all provided user fields'
);

-- Update user with null optional fields
select update_user_details(
    :'userID'::uuid,
    jsonb_build_object(
        'name', 'Final User',
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
    get_user_by_id(:'userID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', (select auth_hash from "user" where user_id = :'userID'::uuid),
        'belongs_to_any_group_team', false,
        'belongs_to_community_team', false,
        'email', 'test@example.com',
        'email_verified', true,
        'name', 'Final User',
        'user_id', :'userID'::text,
        'username', 'testuser'
    ),
    'Should handle null values for optional fields correctly'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
