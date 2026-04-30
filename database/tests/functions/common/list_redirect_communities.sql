-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '00000000-0000-0000-0000-000000000001'
\set fallbackCommunityID '00000000-0000-0000-0000-000000000002'
\set inactiveCommunityID '00000000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (:'activeCommunityID', 'active-community', 'Active Community', 'An active community', 'https://example.com/logo-active.png', 'https://example.com/banner-mobile-active.png', 'https://example.com/banner-active.png'),
    (:'fallbackCommunityID', 'fallback-community', 'Fallback Community', 'A community with a fallback URL', 'https://example.com/logo-fallback.png', 'https://example.com/banner-mobile-fallback.png', 'https://example.com/banner-fallback.png'),
    (:'inactiveCommunityID', 'inactive-community', 'Inactive Community', 'A disabled community', 'https://example.com/logo-inactive.png', 'https://example.com/banner-mobile-inactive.png', 'https://example.com/banner-inactive.png');

update community
set active = false
where community_id = :'inactiveCommunityID'::uuid;

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
        select jsonb_agg(row_to_json(r) order by r.community_name)
        from list_redirect_communities() r
    ),
    '[
        {"community_name": "active-community", "base_legacy_url": null},
        {"community_name": "fallback-community", "base_legacy_url": "https://legacy.example.org"}
    ]'::jsonb,
    'Should return active communities ordered by community name'
);

-- Should return legacy fallback URLs when configured
select is(
    (
        select base_legacy_url
        from list_redirect_communities()
        where community_name = 'fallback-community'
    ),
    'https://legacy.example.org',
    'Should return legacy fallback URLs when configured'
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
