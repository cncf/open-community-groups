-- Tests group-level external-payments settings context.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e07c0000-0000-0000-0000-000000000001'
\set groupCategoryID 'e07c0000-0000-0000-0000-000000000002'
\set groupEligibleID 'e07c0000-0000-0000-0000-000000000003'
\set groupIneligibleID 'e07c0000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and group categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Operator allowlist used by the eligible-group scenario
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Allowlisted group with the toggle enabled
select fx_group(:'groupEligibleID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true
));

-- Group whose country is not allowlisted
select fx_group(:'groupIneligibleID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return eligibility, toggle, and window limits for an allowlisted group
select is(
    get_group_external_payments_context(
        :'communityID'::uuid,
        :'groupEligibleID'::uuid
    ),
    jsonb_build_object(
        'configured', true,
        'country_code', 'KR',
        'default_payment_window_hours', 72,
        'eligible', true,
        'enabled', true,
        'max_payment_window_hours', 336
    ),
    'Should return eligibility, toggle, and window limits for an allowlisted group'
);

-- Should return ineligible context for a group outside the allowlist
select is(
    get_group_external_payments_context(
        :'communityID'::uuid,
        :'groupIneligibleID'::uuid
    ),
    jsonb_build_object(
        'configured', true,
        'country_code', 'US',
        'default_payment_window_hours', 72,
        'eligible', false,
        'enabled', false,
        'max_payment_window_hours', 336
    ),
    'Should return ineligible context for a group outside the allowlist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
