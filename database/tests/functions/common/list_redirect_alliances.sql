-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeAllianceID '00000000-0000-0000-0000-000000000001'
\set fallbackAllianceID '00000000-0000-0000-0000-000000000002'
\set inactiveAllianceID '00000000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (:'activeAllianceID', 'active-alliance', 'Active Alliance', 'An active alliance', 'https://example.com/logo-active.png', 'https://example.com/banner-mobile-active.png', 'https://example.com/banner-active.png'),
    (:'fallbackAllianceID', 'fallback-alliance', 'Fallback Alliance', 'A alliance with a fallback URL', 'https://example.com/logo-fallback.png', 'https://example.com/banner-mobile-fallback.png', 'https://example.com/banner-fallback.png'),
    (:'inactiveAllianceID', 'inactive-alliance', 'Inactive Alliance', 'A disabled alliance', 'https://example.com/logo-inactive.png', 'https://example.com/banner-mobile-inactive.png', 'https://example.com/banner-inactive.png');

update alliance
set active = false
where alliance_id = :'inactiveAllianceID'::uuid;

-- Redirect settings
insert into alliance_redirect_settings (
    alliance_id,

    base_legacy_url
) values
    (:'fallbackAllianceID', 'https://legacy.example.org'),
    (:'inactiveAllianceID', 'https://inactive.example.org');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return active alliances ordered by alliance name
select is(
    (
        select jsonb_agg(row_to_json(r) order by r.alliance_name)
        from list_redirect_alliances() r
    ),
    '[
        {"alliance_name": "active-alliance", "base_legacy_url": null},
        {"alliance_name": "fallback-alliance", "base_legacy_url": "https://legacy.example.org"}
    ]'::jsonb,
    'Should return active alliances ordered by alliance name'
);

-- Should return legacy fallback URLs when configured
select is(
    (
        select base_legacy_url
        from list_redirect_alliances()
        where alliance_name = 'fallback-alliance'
    ),
    'https://legacy.example.org',
    'Should return legacy fallback URLs when configured'
);

-- Should exclude inactive alliances
select ok(
    not exists(
        select 1
        from list_redirect_alliances()
        where alliance_name = 'inactive-alliance'
    ),
    'Should exclude inactive alliances'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
