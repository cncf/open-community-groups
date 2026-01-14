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
    banner_url
) values
    (:'community1ID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner.png'),
    (:'community2ID', 'inactive-community', 'Inactive Community', 'An inactive community', 'https://example.com/logo2.png', 'https://example.com/banner2.png');

-- Deactivate second community
update community set active = false where community_id = :'community2ID';

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return name for active community
select is(
    get_community_name_by_id(:'community1ID'),
    'test-community',
    'Should return name for active community'
);

-- Should return null for inactive community
select is(
    get_community_name_by_id(:'community2ID'),
    null,
    'Should return null for inactive community'
);

-- Should return null for non-existing community
select is(
    get_community_name_by_id('00000000-0000-0000-0000-000000000099'),
    null,
    'Should return null for non-existing community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
