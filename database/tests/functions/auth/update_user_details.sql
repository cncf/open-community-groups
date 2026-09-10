-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set user2ID '0a0a0000-0000-0000-0000-000000000001'
\set user3ID '0a0a0000-0000-0000-0000-000000000002'
\set user4ID '0a0a0000-0000-0000-0000-000000000003'
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
select fx_user(:'user2ID', jsonb_build_object(
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

-- User with populated optional fields cleared by explicit null values
select fx_user(:'user3ID', jsonb_build_object(
    'bio', 'Third user bio',
    'bluesky_url', 'https://bsky.app/profile/third',
    'city', 'Portland',
    'company', 'Third Company',
    'country', 'Canada',
    'email', 'test3@example.com',
    'facebook_url', 'https://facebook.com/third',
    'github_url', 'https://github.com/third',
    'interests', array['cooking', 'travel'],
    'linkedin_url', 'https://linkedin.com/in/third',
    'photo_url', 'https://example.com/third.jpg',
    'timezone', 'America/New_York',
    'twitter_url', 'https://twitter.com/third',
    'username', 'testuser3',
    'website_url', 'https://example.com/third'
));

-- User with populated optional fields cleared by empty string values
select fx_user(:'user4ID', jsonb_build_object(
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
select lives_ok(
    format(
        $$select update_user_details(%L::uuid, %L::jsonb)$$,
        :'userID',
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
            "optional_notifications_enabled": false,
            "photo_url": "https://example.com/photo.jpg",
            "timezone": "America/Los_Angeles",
            "title": "Software Engineer",
            "twitter_url": "https://twitter.com/updateduser",
            "website_url": "https://example.com/updateduser"
        }$$
    ),
    'Should execute update with all provided user fields'
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
        "email": "test-update-user-details@example.com",
        "email_verified": true,
        "optional_notifications_enabled": false,
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
select lives_ok(
    format(
        $$select update_user_details(%L::uuid, %L::jsonb)$$,
        :'user2ID',
        $${
            "name": "Updated Name Only"
        }$$
    ),
    'Should execute update when only name is provided'
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
        "optional_notifications_enabled": true,
        "name": "Updated Name Only",
        "username": "testuser2"
    }'::jsonb,
    'Should clear optional fields when only name is provided'
);

-- Update user with required field and explicit null values for optional fields
select lives_ok(
    format(
        $$select update_user_details(%L::uuid, %L::jsonb)$$,
        :'user3ID',
        $${
            "name": "Explicitly Nulled User",
            "bio": null,
            "bluesky_url": null,
            "city": null,
            "company": null,
            "country": null,
            "facebook_url": null,
            "github_url": null,
            "interests": null,
            "linkedin_url": null,
            "photo_url": null,
            "timezone": null,
            "title": null,
            "twitter_url": null,
            "website_url": null
        }$$
    ),
    'Should execute update with explicit null optional fields'
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
        "optional_notifications_enabled": true,
        "name": "Explicitly Nulled User",
        "username": "testuser3"
    }'::jsonb,
    'Should treat explicit null values the same as omitted fields'
);

-- Update user with empty string values for null-normalized fields
select lives_ok(
    format(
        $$select update_user_details(%L::uuid, %L::jsonb)$$,
        :'user4ID',
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
        }$$
    ),
    'Should execute update with empty string optional fields'
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
    $$, :'user4ID'),
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
