-- Tests listing the groups recently added to a site without groups.
-- Split from get_site_recently_added_groups.sql because this scenario requires
-- no groups, which contradicts the base file's seed data.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return empty array when no groups exist
select is(
    get_site_recently_added_groups()::jsonb,
    '[]'::jsonb,
    'Should return empty array when no groups exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
