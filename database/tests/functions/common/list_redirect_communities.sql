-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '0c130000-0000-0000-0000-000000000001'
\set fallbackCommunityID '0c130000-0000-0000-0000-000000000002'
\set inactiveCommunityID '0c130000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    active,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'activeCommunityID',
    true,
    'https://example.com/banner-mobile-active.png',
    'https://example.com/banner-active.png',
    'An active community',
    'Active Community',
    'https://example.com/logo-active.png',
    'active-community'
), (
    :'fallbackCommunityID',
    true,
    'https://example.com/banner-mobile-fallback.png',
    'https://example.com/banner-fallback.png',
    'A community with a fallback URL',
    'Fallback Community',
    'https://example.com/logo-fallback.png',
    'fallback-community'
), (
    :'inactiveCommunityID',
    false,
    'https://example.com/banner-mobile-inactive.png',
    'https://example.com/banner-inactive.png',
    'A disabled community',
    'Inactive Community',
    'https://example.com/logo-inactive.png',
    'inactive-community'
);

-- Redirect settings
insert into community_redirect_settings (
    community_id,

    base_legacy_url
) values
    (:'fallbackCommunityID', 'https://legacy.example.org'),
    (:'inactiveCommunityID', 'https://inactive.example.org');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return active communities ordered by community name
select is(
    (
        select jsonb_agg(row_to_json(r))
        from list_redirect_communities() r
    ),
    '[
        {"community_name": "active-community", "base_legacy_url": null},
        {"community_name": "fallback-community", "base_legacy_url": "https://legacy.example.org"}
    ]'::jsonb,
    'Should return active communities ordered by community name'
);

-- Should exclude inactive communities
select ok(
    not exists(
        select 1
        from list_redirect_communities()
        where community_name = 'inactive-community'
    ),
    'Should exclude inactive communities'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
