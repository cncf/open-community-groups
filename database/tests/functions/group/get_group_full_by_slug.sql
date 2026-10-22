-- Tests get_group_full_by_slug resolves public groups by slug or pretty slug within a community.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '6a010000-0000-0000-0000-000000000001'
\set communityOtherID '6a010000-0000-0000-0000-000000000002'
\set groupCategoryID '6a010000-0000-0000-0000-000000000003'
\set groupCategoryOtherID '6a010000-0000-0000-0000-000000000004'
\set groupID '6a010000-0000-0000-0000-000000000005'
\set groupInactiveID '6a010000-0000-0000-0000-000000000006'
\set groupOtherCommunityID '6a010000-0000-0000-0000-000000000007'
\set groupPrettySlugID '6a010000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community queried by the slug lookups
select fx_community(:'communityID');

-- Other community reusing the same group slug
select fx_community(:'communityOtherID');

-- Group category for the queried community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category for the other community
select fx_group_category(:'groupCategoryOtherID', :'communityOtherID');

-- Group resolved by its slug
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'slug', 'abc1234'
));

-- Inactive group excluded from slug lookup
select fx_group(:'groupInactiveID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'slug', 'inactive-kubernetes-nyc'
));

-- Group in the other community with the same slug
select fx_group(:'groupOtherCommunityID', :'communityOtherID', :'groupCategoryOtherID', jsonb_build_object(
    'slug', 'abc1234'
));

-- Group resolved by its pretty slug
select fx_group(:'groupPrettySlugID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'slug_pretty', 'kubernetes-nyc'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should resolve group by pretty slug
select is(
    get_group_full_by_slug(:'communityID'::uuid, 'kubernetes-nyc')::jsonb->>'group_id',
    :'groupPrettySlugID',
    'Should resolve group by pretty slug'
);

-- Should return null when the matching group is inactive
select ok(
    get_group_full_by_slug(:'communityID'::uuid, 'inactive-kubernetes-nyc') is null,
    'Should return null when the matching group is inactive'
);

-- Should return null with non-existing group slug
select ok(
    get_group_full_by_slug(:'communityID'::uuid, 'non-existing-group') is null,
    'Should return null with non-existing group slug'
);

-- Should return the full group details of the matching group
select is(
    get_group_full_by_slug(:'communityID'::uuid, 'abc1234')::jsonb,
    get_group_full(:'communityID'::uuid, :'groupID'::uuid)::jsonb,
    'Should return the full group details of the matching group'
);

-- Should scope slug lookup to the requested community
select is(
    jsonb_build_array(
        get_group_full_by_slug(:'communityID'::uuid, 'abc1234')::jsonb->>'group_id',
        get_group_full_by_slug(:'communityOtherID'::uuid, 'abc1234')::jsonb->>'group_id'
    ),
    jsonb_build_array(:'groupID', :'groupOtherCommunityID'),
    'Should scope slug lookup to the requested community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
