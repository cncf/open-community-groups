-- Tests site constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set siteFirstID 'c00e0000-0000-0000-0000-000000000001'
\set siteSecondID 'c00e0000-0000-0000-0000-000000000002'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept the first site row
select lives_ok(
    format(
        $$
            insert into site (site_id, description, theme, title)
            values (%L, 'First site description', '{"primary_color": "#c00e01"}'::jsonb, 'First site')
        $$,
        :'siteFirstID'
    ),
    'Should accept the first site row'
);

-- Should reject a second site row
select throws_ok(
    format(
        $$
            insert into site (site_id, description, theme, title)
            values (%L, 'Second site description', '{"primary_color": "#c00e02"}'::jsonb, 'Second site')
        $$,
        :'siteSecondID'
    ),
    '23505',
    'duplicate key value violates unique constraint "site_singleton_idx"',
    'Should reject a second site row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
