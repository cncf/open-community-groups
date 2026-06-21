-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID '00000000-0000-0000-0000-000000000001'
\set alliance2ID '00000000-0000-0000-0000-000000000002'

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
    (:'alliance1ID', 'test-alliance', 'Test Alliance', 'A test alliance', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'alliance2ID', 'inactive-alliance', 'Inactive Alliance', 'An inactive alliance', 'https://example.com/logo2.png', 'https://example.com/banner_mobile2.png', 'https://example.com/banner2.png');

-- Deactivate second alliance
update alliance set active = false where alliance_id = :'alliance2ID';

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return name for active alliance
select is(
    get_alliance_name_by_id(:'alliance1ID'),
    'test-alliance',
    'Should return name for active alliance'
);

-- Should return null for inactive alliance
select is(
    get_alliance_name_by_id(:'alliance2ID'),
    null,
    'Should return null for inactive alliance'
);

-- Should return null for non-existing alliance
select is(
    get_alliance_name_by_id('00000000-0000-0000-0000-000000000099'),
    null,
    'Should return null for non-existing alliance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
