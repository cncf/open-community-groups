-- Tests community constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c00f0000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community receiving the values written by the constraint scenarios
select fx_community(:'communityID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a blank dark banner URL
select throws_ok(
    format(
        $$update community set banner_dark_url = ' ' where community_id = %L::uuid$$,
        :'communityID'
    ),
    '23514',
    'new row for relation "community" violates check constraint "community_banner_dark_url_check"',
    'Should reject a blank dark banner URL'
);

-- Should reject a blank dark logo URL
select throws_ok(
    format(
        $$update community set logo_dark_url = ' ' where community_id = %L::uuid$$,
        :'communityID'
    ),
    '23514',
    'new row for relation "community" violates check constraint "community_logo_dark_url_check"',
    'Should reject a blank dark logo URL'
);

-- Should reject a blank dark mobile banner URL
select throws_ok(
    format(
        $$update community set banner_mobile_dark_url = ' ' where community_id = %L::uuid$$,
        :'communityID'
    ),
    '23514',
    'new row for relation "community" violates check constraint "community_banner_mobile_dark_url_check"',
    'Should reject a blank dark mobile banner URL'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
