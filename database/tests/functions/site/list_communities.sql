-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set community3ID '00000000-0000-0000-0000-000000000003'

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
    (:'community1ID', 'alpha-community', 'Alpha Community', 'First community', 'https://example.com/alpha-logo.png', 'https://example.com/alpha-banner_mobile.png', 'https://example.com/alpha-banner.png'),
    (:'community2ID', 'beta-community', 'Beta Community', 'Second community', 'https://example.com/beta-logo.png', 'https://example.com/beta-banner_mobile.png', 'https://example.com/beta-banner.png'),
    (:'community3ID', 'gamma-community', 'Gamma Community', 'Third community', 'https://example.com/gamma-logo.png', 'https://example.com/gamma-banner_mobile.png', 'https://example.com/gamma-banner.png');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all active communities ordered by display_name
select is(
    list_communities()::jsonb,
    '[
        {
            "banner_mobile_url": "https://example.com/alpha-banner_mobile.png",
            "banner_url": "https://example.com/alpha-banner.png",
            "community_id": "00000000-0000-0000-0000-000000000001",
            "display_name": "Alpha Community",
            "logo_url": "https://example.com/alpha-logo.png",
            "name": "alpha-community"
        },
        {
            "banner_mobile_url": "https://example.com/beta-banner_mobile.png",
            "banner_url": "https://example.com/beta-banner.png",
            "community_id": "00000000-0000-0000-0000-000000000002",
            "display_name": "Beta Community",
            "logo_url": "https://example.com/beta-logo.png",
            "name": "beta-community"
        },
        {
            "banner_mobile_url": "https://example.com/gamma-banner_mobile.png",
            "banner_url": "https://example.com/gamma-banner.png",
            "community_id": "00000000-0000-0000-0000-000000000003",
            "display_name": "Gamma Community",
            "logo_url": "https://example.com/gamma-logo.png",
            "name": "gamma-community"
        }
    ]'::jsonb,
    'Should return all active communities ordered by display_name'
);

-- Should exclude inactive communities
update community set active = false where community_id = :'community2ID';
select is(
    list_communities()::jsonb,
    '[
        {
            "banner_mobile_url": "https://example.com/alpha-banner_mobile.png",
            "banner_url": "https://example.com/alpha-banner.png",
            "community_id": "00000000-0000-0000-0000-000000000001",
            "display_name": "Alpha Community",
            "logo_url": "https://example.com/alpha-logo.png",
            "name": "alpha-community"
        },
        {
            "banner_mobile_url": "https://example.com/gamma-banner_mobile.png",
            "banner_url": "https://example.com/gamma-banner.png",
            "community_id": "00000000-0000-0000-0000-000000000003",
            "display_name": "Gamma Community",
            "logo_url": "https://example.com/gamma-logo.png",
            "name": "gamma-community"
        }
    ]'::jsonb,
    'Should exclude inactive communities'
);

-- Should return empty array when no communities exist
delete from community;
select is(
    list_communities()::jsonb,
    '[]'::jsonb,
    'Should return empty array when no communities exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
