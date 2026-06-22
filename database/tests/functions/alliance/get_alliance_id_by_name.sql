-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeAllianceID '0d010000-0000-0000-0000-000000000001'
\set inactiveAllianceID '0d010000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'activeAllianceID',
    'alliance-id-lookup',
    'Alliance ID Lookup',
    'Alliance used for name lookups',
    'https://example.com/alliance-id-lookup-banner-mobile.png',
    'https://example.com/alliance-id-lookup-banner.png',
    'https://example.com/alliance-id-lookup-logo.png'
);

insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    active,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'inactiveAllianceID',
    'inactive-alliance-id-lookup',
    'Inactive Alliance ID Lookup',
    'Inactive alliance used for name lookups',
    false,
    'https://example.com/inactive-alliance-id-lookup-banner-mobile.png',
    'https://example.com/inactive-alliance-id-lookup-banner.png',
    'https://example.com/inactive-alliance-id-lookup-logo.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return alliance_id for active alliance
select is(
    get_alliance_id_by_name('alliance-id-lookup'),
    :'activeAllianceID'::uuid,
    'Should return alliance_id for active alliance'
);

-- Should return null for inactive alliance
select is(
    get_alliance_id_by_name('inactive-alliance-id-lookup'),
    null,
    'Should return null for inactive alliance'
);

-- Should return null for non-existing alliance
select is(
    get_alliance_id_by_name('non-existing-alliance'),
    null,
    'Should return null for non-existing alliance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
