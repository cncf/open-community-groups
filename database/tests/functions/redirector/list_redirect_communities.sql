-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '0c000000-0000-0000-0000-000000000001'
\set fallbackCommunityID '0c000000-0000-0000-0000-000000000002'
\set inactiveCommunityID '0c000000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
select fx_community(:'activeCommunityID', jsonb_build_object('name', 'active-community-list-redirect-communities'));
select fx_community(:'fallbackCommunityID', jsonb_build_object('name', 'fallback-community'));
select fx_community(:'inactiveCommunityID', jsonb_build_object(
    'active', false,
    'name', 'inactive-community-list-redirect-communities'
));

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
        {"community_name": "active-community-list-redirect-communities", "base_legacy_url": null},
        {"community_name": "fallback-community", "base_legacy_url": "https://legacy.example.org"}
    ]'::jsonb,
    'Should return active communities ordered by community name'
);

-- Should exclude inactive communities
select ok(
    not exists(
        select 1
        from list_redirect_communities()
        where community_name = 'inactive-community-list-redirect-communities'
    ),
    'Should exclude inactive communities'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
