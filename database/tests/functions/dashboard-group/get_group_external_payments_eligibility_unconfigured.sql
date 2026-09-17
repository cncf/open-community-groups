-- Tests external-payments eligibility of a group country without operator config.
-- Split from get_group_external_payments_eligibility.sql because that file seeds
-- the singleton external_payments_config row this scenario requires to be absent.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e0810000-0000-0000-0000-000000000001'
\set groupCategoryID 'e0810000-0000-0000-0000-000000000002'
\set groupID 'e0810000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and group categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group whose operator config row is absent
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report a stored country as ineligible when no operator config row is synced
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupID'::uuid),
    false,
    'Should report a stored country as ineligible when no operator config row is synced'
);

-- Should report a submitted country as ineligible when no operator config row is synced
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupID'::uuid, 'KR'),
    false,
    'Should report a submitted country as ineligible when no operator config row is synced'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
