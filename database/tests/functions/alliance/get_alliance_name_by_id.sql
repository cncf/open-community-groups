-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeAllianceID '0d020000-0000-0000-0000-000000000001'
\set inactiveAllianceID '0d020000-0000-0000-0000-000000000002'
\set unknownAllianceID '0d020000-0000-0000-0000-000000000003'

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
    'alliance-name-lookup',
    'Alliance Name Lookup',
    'Alliance used for ID lookups',
    'https://example.com/alliance-name-lookup-banner-mobile.png',
    'https://example.com/alliance-name-lookup-banner.png',
    'https://example.com/alliance-name-lookup-logo.png'
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
    'inactive-alliance-name-lookup',
    'Inactive Alliance Name Lookup',
    'Inactive alliance used for ID lookups',
    false,
    'https://example.com/inactive-alliance-name-lookup-banner-mobile.png',
    'https://example.com/inactive-alliance-name-lookup-banner.png',
    'https://example.com/inactive-alliance-name-lookup-logo.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return name for active alliance
select is(
    get_alliance_name_by_id(:'activeAllianceID'),
    'alliance-name-lookup',
    'Should return name for active alliance'
);

-- Should return null for inactive alliance
select is(
    get_alliance_name_by_id(:'inactiveAllianceID'),
    null,
    'Should return null for inactive alliance'
);

-- Should return null for non-existing alliance
select is(
    get_alliance_name_by_id(:'unknownAllianceID'),
    null,
    'Should return null for non-existing alliance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
