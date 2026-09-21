-- Tests group-level external-payments rail selection.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e0e50000-0000-0000-0000-000000000001'
\set groupCategoryID 'e0e50000-0000-0000-0000-000000000002'
\set groupDisabledID 'e0e50000-0000-0000-0000-000000000003'
\set groupNamelessID 'e0e50000-0000-0000-0000-000000000004'
\set groupSelectedID 'e0e50000-0000-0000-0000-000000000005'
\set groupUnlistedID 'e0e50000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and group categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Operator allowlist used by the rail-selection scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Allowlisted group with the external-payments toggle off
select fx_group(:'groupDisabledID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR'
));

-- Allowlisted enabled group without the external payee legal name
select fx_group(:'groupNamelessID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true
));

-- Allowlisted enabled group with the external payee legal name
select fx_group(:'groupSelectedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'External Payee Co'
));

-- Enabled group whose country is outside the allowlist
select fx_group(:'groupUnlistedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'External Payee Co'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report selected when the toggle is on and the country is allowlisted
select is(
    is_group_external_payments_selected(:'groupSelectedID'::uuid),
    true,
    'Should report selected when the toggle is on and the country is allowlisted'
);

-- Should report selected without the external payee legal name
select is(
    is_group_external_payments_selected(:'groupNamelessID'::uuid),
    true,
    'Should report selected without the external payee legal name'
);

-- Should report unselected for an unknown group
select is(
    is_group_external_payments_selected('00000000-0000-0000-0000-000000000000'::uuid),
    false,
    'Should report unselected for an unknown group'
);

-- Should report unselected when the group country is not allowlisted
select is(
    is_group_external_payments_selected(:'groupUnlistedID'::uuid),
    false,
    'Should report unselected when the group country is not allowlisted'
);

-- Should report unselected when the group toggle is off
select is(
    is_group_external_payments_selected(:'groupDisabledID'::uuid),
    false,
    'Should report unselected when the group toggle is off'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
