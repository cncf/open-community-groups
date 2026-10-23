-- Tests returning the site settings without a site configuration.
-- Split from get_site_settings.sql because the site singleton seeded there
-- must be absent here.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return null when no site exists
select ok(
    get_site_settings() is null,
    'Should return null when no site exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
