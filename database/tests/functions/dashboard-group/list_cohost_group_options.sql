-- Tests listing co-host group options.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e5080000-0000-0000-0000-000000000001'
\set communityID 'e5080000-0000-0000-0000-000000000002'
\set excludedGroupID 'e5080000-0000-0000-0000-000000000003'
\set groupCategoryID 'e5080000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and category
select fx_community(:'communityID', jsonb_build_object(
    'display_name', 'Options Community',
    'logo_url', 'https://example.test/options-community.png',
    'name', 'options-community'
));
select fx_group_category(:'groupCategoryID', :'communityID');

-- Groups used to include and exclude options
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', null,
    'name', 'Available Group',
    'slug', 'available-group',
    'slug_pretty', 'available'
));
select fx_group(:'excludedGroupID', :'communityID', :'groupCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return active groups except the excluded group
select is(
    list_cohost_group_options(:'communityID'::uuid, :'excludedGroupID'::uuid)::jsonb,
    format('[{
        "community_display_name": "Options Community",
        "community_name": "options-community",
        "group_id": "%s",
        "logo_url": "https://example.test/options-community.png",
        "name": "Available Group",
        "slug": "available-group",
        "slug_pretty": "available"
    }]', :'cohostGroupID')::jsonb,
    'Should return active groups except the excluded group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
