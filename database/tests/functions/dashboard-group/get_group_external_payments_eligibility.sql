-- Tests resolving the external-payments eligibility of a group's resulting country.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e0800000-0000-0000-0000-000000000001'
\set groupAllowlistedID 'e0800000-0000-0000-0000-000000000003'
\set groupCategoryID 'e0800000-0000-0000-0000-000000000002'
\set groupDeletedID 'e0800000-0000-0000-0000-000000000006'
\set groupMissingID 'e0800000-0000-0000-0000-000000000008'
\set groupNoCountryID 'e0800000-0000-0000-0000-000000000005'
\set groupNotAllowlistedID 'e0800000-0000-0000-0000-000000000004'
\set otherCommunityID 'e0800000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and group categories
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Operator allowlist used by the allowlisted-country scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Group whose stored country is allowlisted
select fx_group(:'groupAllowlistedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR'
));

-- Deleted group whose stored country is allowlisted
select fx_group(:'groupDeletedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'country_code', 'KR',
    'deleted', true,
    'deleted_at', '2024-02-01 00:00:00+00'
));

-- Group without a stored country
select fx_group(:'groupNoCountryID', :'communityID', :'groupCategoryID');

-- Group whose stored country is not allowlisted
select fx_group(:'groupNotAllowlistedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report a deleted group as ineligible
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupDeletedID'::uuid),
    false,
    'Should report a deleted group as ineligible'
);

-- Should report a group in another community as ineligible
select is(
    get_group_external_payments_eligibility(:'otherCommunityID'::uuid, :'groupAllowlistedID'::uuid),
    false,
    'Should report a group in another community as ineligible'
);

-- Should report a missing group as ineligible
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupMissingID'::uuid),
    false,
    'Should report a missing group as ineligible'
);

-- Should report an omitted country as eligible when the stored country is allowlisted
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupAllowlistedID'::uuid),
    true,
    'Should report an omitted country as eligible when the stored country is allowlisted'
);

-- Should report an omitted country as ineligible when the stored country is not allowlisted
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupNotAllowlistedID'::uuid),
    false,
    'Should report an omitted country as ineligible when the stored country is not allowlisted'
);

-- Should report an omitted country as ineligible when no country is stored
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupNoCountryID'::uuid),
    false,
    'Should report an omitted country as ineligible when no country is stored'
);

-- Should treat an explicit empty country as clearing the stored allowlisted country
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupAllowlistedID'::uuid, ''),
    false,
    'Should treat an explicit empty country as clearing the stored allowlisted country'
);

-- Should use a submitted allowlisted country over a stored non-allowlisted one
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupNotAllowlistedID'::uuid, 'KR'),
    true,
    'Should use a submitted allowlisted country over a stored non-allowlisted one'
);

-- Should use a submitted non-allowlisted country over a stored allowlisted one
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupAllowlistedID'::uuid, 'FR'),
    false,
    'Should use a submitted non-allowlisted country over a stored allowlisted one'
);

-- Should normalize a lowercase submitted country before matching the allowlist
select is(
    get_group_external_payments_eligibility(:'communityID'::uuid, :'groupNotAllowlistedID'::uuid, 'kr'),
    true,
    'Should normalize a lowercase submitted country before matching the allowlist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
