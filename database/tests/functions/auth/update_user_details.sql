-- Tests updating user profile details.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set emptyStringUserID '0a0a0000-0000-0000-0000-000000000003'
\set nameOnlyUserID '0a0a0000-0000-0000-0000-000000000001'
\set userID '0a0a0000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User updated with all updateable fields
select fx_user(:'userID', jsonb_build_object(
    'email', 'test-update-user-details@example.com',
    'username', 'testuser-update-user-details'
));

-- User with populated optional fields cleared by a name-only update
select fx_user(:'nameOnlyUserID', jsonb_build_object(
    'bio', 'Original bio',
    'bluesky_url', 'https://bsky.app/profile/original',
    'city', 'Seattle',
    'company', 'Original Company',
    'country', 'USA',
    'email', 'test2@example.com',
    'facebook_url', 'https://facebook.com/original',
    'github_url', 'https://github.com/original',
    'interests', array['reading', 'gaming'],
    'linkedin_url', 'https://linkedin.com/in/original',
    'photo_url', 'https://example.com/original.jpg',
    'timezone', 'America/Los_Angeles',
    'twitter_url', 'https://twitter.com/original',
    'username', 'testuser2',
    'website_url', 'https://example.com/original'
));

-- User with populated optional fields cleared by empty string values
select fx_user(:'emptyStringUserID', jsonb_build_object(
    'bio', 'Fourth user bio',
    'bluesky_url', 'https://bsky.app/profile/fourth',
    'city', 'Austin',
    'company', 'Fourth Company',
    'country', 'USA',
    'facebook_url', 'https://facebook.com/fourth',
    'github_url', 'https://github.com/fourth',
    'interests', array['cycling', 'music'],
    'linkedin_url', 'https://linkedin.com/in/fourth',
    'photo_url', 'https://example.com/fourth.jpg',
    'timezone', 'America/Chicago',
    'twitter_url', 'https://twitter.com/fourth',
    'website_url', 'https://example.com/fourth'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Update user with all updateable fields
select update_user_details(
    :'userID'::uuid,
    $${
        "name": "Updated User",
        "bio": "This is my bio",
        "bluesky_url": "https://bsky.app/profile/updateduser",
        "city": "San Francisco",
        "company": "Example Corp",
        "country": "USA",
        "facebook_url": "https://facebook.com/updateduser",
        "github_url": "https://github.com/updateduser",
        "interests": ["programming", "music", "sports"],
        "linkedin_url": "https://linkedin.com/in/updateduser",
        "photo_url": "https://example.com/photo.jpg",
        "timezone": "America/Los_Angeles",
        "title": "Software Engineer",
        "twitter_url": "https://twitter.com/updateduser",
        "website_url": "https://example.com/updateduser"
    }$$::jsonb
);

-- Should persist all provided user fields
select is(
    get_user_by_id(:'userID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', (select auth_hash from "user" where user_id = :'userID'::uuid),
        'user_id', :'userID'::text
    ) || '{
        "belongs_to_any_group_team": false,
        "belongs_to_community_team": false,
        "email": "test-update-user-details@example.com",
        "email_verified": true,
        "name": "Updated User",
        "username": "testuser-update-user-details",
        "bio": "This is my bio",
        "bluesky_url": "https://bsky.app/profile/updateduser",
        "city": "San Francisco",
        "company": "Example Corp",
        "country": "USA",
        "facebook_url": "https://facebook.com/updateduser",
        "github_url": "https://github.com/updateduser",
        "interests": ["programming", "music", "sports"],
        "linkedin_url": "https://linkedin.com/in/updateduser",
        "photo_url": "https://example.com/photo.jpg",
        "timezone": "America/Los_Angeles",
        "title": "Software Engineer",
        "twitter_url": "https://twitter.com/updateduser",
        "website_url": "https://example.com/updateduser"
    }'::jsonb,
    'Should persist all provided user fields'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            resource_type,
            resource_id
        from audit_log
    $$,
    format($$
        values (
            'user_details_updated',
            %L::uuid,
            'testuser-update-user-details',
            'user',
            %L::uuid
        )
    $$, :'userID', :'userID'),
    'Should create the expected audit row'
);

-- Update user with only required field (name), rest are null
select update_user_details(
    :'nameOnlyUserID'::uuid,
    '{"name": "Updated Name Only"}'::jsonb
);

-- Should clear optional fields when only name is provided
select is(
    get_user_by_id(:'nameOnlyUserID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', (select auth_hash from "user" where user_id = :'nameOnlyUserID'::uuid),
        'user_id', :'nameOnlyUserID'::text
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

-- Update user with empty string values for null-normalized fields
select update_user_details(
    :'emptyStringUserID'::uuid,
    $${
        "name": "Empty String User",
        "bio": "",
        "bluesky_url": "",
        "city": "",
        "company": "",
        "country": "",
        "facebook_url": "",
        "github_url": "",
        "linkedin_url": "",
        "photo_url": "",
        "timezone": "",
        "title": "",
        "twitter_url": "",
        "website_url": ""
    }$$::jsonb
);

-- Should normalize empty string values to null
select results_eq(
    format($$
        select
            bio,
            bluesky_url,
            city,
            company,
            country,
            facebook_url,
            github_url,
            linkedin_url,
            photo_url,
            timezone,
            title,
            twitter_url,
            website_url
        from "user"
        where user_id = %L::uuid
    $$, :'emptyStringUserID'),
    $$
        values (
            null::text,
            null::text,
            null::text,
            null::text,
            null::text,
            null::text,
            null::text,
            null::text,
            null::text,
            null::text,
            null::text,
            null::text,
            null::text
        )
    $$,
    'Should normalize empty string values to null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
