-- Tests listing co-host group options.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e5080000-0000-0000-0000-000000000001'
\set excludedGroupID 'e5080000-0000-0000-0000-000000000002'
\set fallbackLogoGroupID 'e5080000-0000-0000-0000-000000000003'
\set groupCategoryID 'e5080000-0000-0000-0000-000000000004'
\set inactiveCommunityCategoryID 'e5080000-0000-0000-0000-000000000005'
\set inactiveCommunityGroupID 'e5080000-0000-0000-0000-000000000006'
\set inactiveCommunityID 'e5080000-0000-0000-0000-000000000007'
\set inactiveGroupID 'e5080000-0000-0000-0000-000000000008'
\set ownLogoGroupID 'e5080000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community whose groups are listed
select fx_community(:'communityID', jsonb_build_object(
    'active', true,
    'display_name', 'Options Community',
    'logo_url', 'https://example.test/options-community.png',
    'name', 'options-community'
));

-- Inactive community whose groups are never listed
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Group categories
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'inactiveCommunityCategoryID', :'inactiveCommunityID');

-- Active group excluded by the caller
select fx_group(:'excludedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'name', 'Excluded Option'
));

-- Active group without a logo or pretty slug, sorted last by name but first by id
select fx_group(:'fallbackLogoGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'logo_url', null,
    'name', 'Zulu Option',
    'slug', 'zulu-option'
));

-- Active group in the inactive community
select fx_group(:'inactiveCommunityGroupID', :'inactiveCommunityID', :'inactiveCommunityCategoryID', jsonb_build_object(
    'active', true,
    'name', 'Inactive Community Option'
));

-- Inactive group in the active community
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'name', 'Inactive Option'
));

-- Active group with its own logo and pretty slug, sorted first by name but last by id
select fx_group(:'ownLogoGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'logo_url', 'https://example.test/alpha-option.png',
    'name', 'Alpha Option',
    'slug', 'alpha-option',
    'slug_pretty', 'alpha-pretty'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return active groups ordered by name except the excluded group
select is(
    list_cohost_group_options(:'communityID'::uuid, :'excludedGroupID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'community_display_name', 'Options Community',
            'community_name', 'options-community',
            'group_id', :'ownLogoGroupID'::uuid,
            'logo_url', 'https://example.test/alpha-option.png',
            'name', 'Alpha Option',
            'slug', 'alpha-option',

            'slug_pretty', 'alpha-pretty'
        ),
        jsonb_build_object(
            'community_display_name', 'Options Community',
            'community_name', 'options-community',
            'group_id', :'fallbackLogoGroupID'::uuid,
            'logo_url', 'https://example.test/options-community.png',
            'name', 'Zulu Option',
            'slug', 'zulu-option'
        )
    ),
    'Should return active groups ordered by name except the excluded group'
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
