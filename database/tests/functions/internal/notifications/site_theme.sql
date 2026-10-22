-- Tests resolving the site theme used by notifications.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set siteLatestID '0c200000-0000-0000-0000-000000000001'
\set siteOlderID '0c200000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Latest site configuration
insert into site (site_id, description, theme, title)
values (
    :'siteLatestID',
    'Latest site description',
    '{"primary_color": "#0c2001"}'::jsonb,
    'Latest site'
);

-- Older site configuration
insert into site (site_id, created_at, description, theme, title)
values (
    :'siteOlderID',
    current_timestamp - interval '1 day',
    'Older site description',
    '{"primary_color": "#0c2002"}'::jsonb,
    'Older site'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the theme of the latest site configuration
select is(
    site_theme(),
    '{"primary_color": "#0c2001"}'::jsonb,
    'Should return the theme of the latest site configuration'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
