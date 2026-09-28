-- Tests list_cohost_group_options filtering and ordering.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alphaGroupID 'e5170000-0000-0000-0000-000000000001'
\set communityID 'e5170000-0000-0000-0000-000000000002'
\set deletedGroupID 'e5170000-0000-0000-0000-000000000003'
\set excludedGroupID 'e5170000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5170000-0000-0000-0000-000000000005'
\set inactiveCommunityGroupID 'e5170000-0000-0000-0000-000000000006'
\set inactiveCommunityID 'e5170000-0000-0000-0000-000000000007'
\set inactiveCommunityCategoryID 'e5170000-0000-0000-0000-000000000008'
\set inactiveGroupID 'e5170000-0000-0000-0000-000000000009'
\set zuluGroupID 'e5170000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and categories
select fx_community(:'communityID', jsonb_build_object('display_name', 'Options Matrix', 'logo_url', 'https://example.test/options-matrix.png', 'name', 'options-matrix'));
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'inactiveCommunityCategoryID', :'inactiveCommunityID');

-- Groups covering option filters and ordering
select fx_group(:'alphaGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('logo_url', null, 'name', 'Alpha Option', 'slug', 'alpha-option'));
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false, 'deleted', true, 'name', 'Deleted Option'));
select fx_group(:'excludedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Excluded Option'));
select fx_group(:'inactiveCommunityGroupID', :'inactiveCommunityID', :'inactiveCommunityCategoryID', jsonb_build_object('name', 'Inactive Community Option'));
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false, 'name', 'Inactive Option'));
select fx_group(:'zuluGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Zulu Option', 'slug', 'zulu-option', 'slug_pretty', 'zulu-pretty'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return active non-deleted groups in the active community except the excluded group
select is(
    (
        select jsonb_agg(item->>'name')
        from jsonb_array_elements(list_cohost_group_options(:'communityID'::uuid, :'excludedGroupID'::uuid)::jsonb) item
    ),
    '["Alpha Option", "Zulu Option"]'::jsonb,
    'Should return active non-deleted groups in the active community except the excluded group'
);

-- Should use the community logo fallback and optional pretty slug
select ok(
    list_cohost_group_options(:'communityID'::uuid, :'excludedGroupID'::uuid)::jsonb
        @> format('[{"group_id":"%s","logo_url":"https://example.test/options-matrix.png"},{"group_id":"%s","slug_pretty":"zulu-pretty"}]', :'alphaGroupID', :'zuluGroupID')::jsonb,
    'Should use the community logo fallback and optional pretty slug'
);

-- Should return an empty array for inactive communities
select is(
    list_cohost_group_options(:'inactiveCommunityID'::uuid, :'excludedGroupID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return an empty array for inactive communities'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
