-- Tests projecting the public profile of a user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set fullUserID 'e5f50000-0000-0000-0000-000000000001'
\set minimalUserID 'e5f50000-0000-0000-0000-000000000002'
\set privateProviderUserID 'e5f50000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User with every public profile field and private fields that must not leak
select fx_user(:'fullUserID', jsonb_build_object(
    'bio', 'Full bio',
    'bluesky_url', 'https://bsky.app/profile/full',
    'city', 'Private City',
    'company', 'ACME',
    'country', 'Private Country',
    'email', 'public-user-profile-full@example.com',
    'facebook_url', 'https://facebook.com/full',
    'github_url', 'https://github.com/full',
    'interests', array['private-interest'],
    'linkedin_url', 'https://linkedin.com/in/full',
    'name', 'Full User',
    'photo_url', 'https://example.com/full.png',
    'provider', jsonb_build_object(
        'github', jsonb_build_object('username', 'full-octocat')
    ),
    'timezone', 'Europe/Madrid',
    'title', 'Engineer',
    'twitter_url', 'https://twitter.com/full',
    'username', 'public-user-profile-full',
    'website_url', 'https://example.com/full'
));

-- User with only the required fields
select fx_user(:'minimalUserID', jsonb_build_object(
    'email', 'public-user-profile-minimal@example.com',
    'username', 'public-user-profile-minimal'
));

-- User whose provider metadata carries private identity keys
select fx_user(:'privateProviderUserID', jsonb_build_object(
    'email', 'public-user-profile-provider@example.com',
    'provider', jsonb_build_object(
        'github', jsonb_build_object('username', '  '),
        'linuxfoundation', jsonb_build_object(
            'issuer', 'https://issuer.example.com',
            'subject', 'auth0|public-user-profile',
            'username', 'lf-profile-user'
        )
    ),
    'username', 'public-user-profile-provider'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include every public profile field only
select is(
    (select public_user_profile(u) from "user" u where u.user_id = :'fullUserID'),
    jsonb_build_object(
        'user_id', :'fullUserID',
        'username', 'public-user-profile-full',

        'bio', 'Full bio',
        'bluesky_url', 'https://bsky.app/profile/full',
        'company', 'ACME',
        'facebook_url', 'https://facebook.com/full',
        'github_url', 'https://github.com/full',
        'linkedin_url', 'https://linkedin.com/in/full',
        'name', 'Full User',
        'photo_url', 'https://example.com/full.png',
        'provider', jsonb_build_object(
            'github', jsonb_build_object('username', 'full-octocat')
        ),
        'title', 'Engineer',
        'twitter_url', 'https://twitter.com/full',
        'website_url', 'https://example.com/full'
    ),
    'Should include every public profile field only'
);

-- Should project provider metadata through the public provider projection
select is(
    (select public_user_profile(u) from "user" u where u.user_id = :'privateProviderUserID'),
    jsonb_build_object(
        'user_id', :'privateProviderUserID',
        'username', 'public-user-profile-provider',

        'provider', jsonb_build_object(
            'linuxfoundation', jsonb_build_object('username', 'lf-profile-user')
        )
    ),
    'Should project provider metadata through the public provider projection'
);

-- Should strip missing optional fields
select is(
    (select public_user_profile(u) from "user" u where u.user_id = :'minimalUserID'),
    jsonb_build_object(
        'user_id', :'minimalUserID',
        'username', 'public-user-profile-minimal'
    ),
    'Should strip missing optional fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
