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

-- Users
insert into "user" (
    user_id,
    name,
    auth_hash,
    bio,
    bluesky_url,
    city,
    company,
    country,
    email,
    email_verified,
    facebook_url,
    github_url,
    interests,
    linkedin_url,
    photo_url,
    timezone,
    title,
    twitter_url,
    username,
    website_url
) values
    (
        :'user2ID',
        'Second User',
        gen_random_bytes(32),
        'Original bio',
        'https://bsky.app/profile/original',
        'Seattle',
        'Original Company',
        'USA',
        'test2@example.com',
        true,
        'https://facebook.com/original',
        'https://github.com/original',
        array['reading', 'gaming'],
        'https://linkedin.com/in/original',
        'https://example.com/original.jpg',
        'America/Los_Angeles',
        'Original Title',
        'https://twitter.com/original',
        'testuser2',
        'https://example.com/original'
    ),
    (
        :'user3ID',
        'Third User',
        gen_random_bytes(32),
        'Third user bio',
        'https://bsky.app/profile/third',
        'Portland',
        'Third Company',
        'Canada',
        'test3@example.com',
        true,
        'https://facebook.com/third',
        'https://github.com/third',
        array['cooking', 'travel'],
        'https://linkedin.com/in/third',
        'https://example.com/third.jpg',
        'America/New_York',
        'Third Title',
        'https://twitter.com/third',
        'testuser3',
        'https://example.com/third'
    ),
    (
        :'user4ID',
        'Fourth User',
        gen_random_bytes(32),
        'Fourth user bio',
        'https://bsky.app/profile/fourth',
        'Austin',
        'Fourth Company',
        'USA',
        'test4@example.com',
        true,
        'https://facebook.com/fourth',
        'https://github.com/fourth',
        array['cycling', 'music'],
        'https://linkedin.com/in/fourth',
        'https://example.com/fourth.jpg',
        'America/Chicago',
        'Fourth Title',
        'https://twitter.com/fourth',
        'testuser4',
        'https://example.com/fourth'
    ),
    (
        :'userID',
        'Original User',
        gen_random_bytes(32),
        null,
        null,
        null,
        null,
        null,
        'test@example.com',
        true,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        'testuser',
        null
    );

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
        "email": "test@example.com",
        "email_verified": true,
        "optional_notifications_enabled": false,
        "name": "Updated User",
        "username": "testuser",
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
            'testuser',
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
