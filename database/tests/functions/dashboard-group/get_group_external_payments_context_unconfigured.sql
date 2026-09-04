-- Tests group-level external-payments settings context without operator config.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e07d0000-0000-0000-0000-000000000001'
\set groupCategoryID 'e07d0000-0000-0000-0000-000000000002'
\set groupID 'e07d0000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and group categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group whose operator config row is absent
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report the operator config as absent when no row is synced
select is(
    get_group_external_payments_context(
        :'communityID'::uuid,
        :'groupID'::uuid
    ),
    jsonb_build_object(
        'configured', false,
        'country_code', 'KR',
        'eligible', false,
        'enabled', true
    ),
    'Should report the operator config as absent when no row is synced'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
