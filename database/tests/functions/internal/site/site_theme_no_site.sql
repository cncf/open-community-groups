-- Tests resolving the site theme without a site configuration.
-- Split from site_theme.sql because the site singleton seeded there must be
-- absent here.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return null when no site configuration exists
select ok(
    site_theme() is null,
    'Should return null when no site configuration exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
