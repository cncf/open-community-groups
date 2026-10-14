-- Tests listing community groups for the community dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c6100000-0000-0000-0000-000000000001'
\set communityOtherID 'c6100000-0000-0000-0000-000000000002'
\set groupActiveID 'c6100000-0000-0000-0000-000000000003'
\set groupCategoryID 'c6100000-0000-0000-0000-000000000004'
\set groupCategoryOtherID 'c6100000-0000-0000-0000-000000000005'
\set groupDeletedID 'c6100000-0000-0000-0000-000000000006'
\set groupInactiveID 'c6100000-0000-0000-0000-000000000007'
\set groupOtherID 'c6100000-0000-0000-0000-000000000008'
\set unknownCommunityID 'c6100000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Inactive community whose groups are listed
select fx_community(:'communityID', jsonb_build_object('active', false));

-- Community whose groups are never listed for the inactive community
select fx_community(:'communityOtherID');

-- Group category of the inactive community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the other community
select fx_group_category(:'groupCategoryOtherID', :'communityOtherID');

-- Active group tagged for text search
select fx_group(:'groupActiveID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'name', 'LCG Alpha Group',
    'tags', array['rust']
));

-- Deleted group never listed
select fx_group(:'groupDeletedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'name', 'LCG Deleted Group'
));

-- Inactive group listed after the active group
select fx_group(:'groupInactiveID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'name', 'LCG Beta Group'
));

-- Active group of the other community
select fx_group(:'groupOtherID', :'communityOtherID', :'groupCategoryOtherID', jsonb_build_object(
    'active', true,
    'name', 'LCG Other Group'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should filter groups by text search query
select is(
    list_community_groups(
        :'communityID'::uuid,
        '{"limit": 10, "offset": 0, "ts_query": "rus"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'groups', jsonb_build_array(
            get_group_summary(:'communityID'::uuid, :'groupActiveID'::uuid)::jsonb
        ),
        'total', 1
    ),
    'Should filter groups by text search query'
);

-- Should list active and inactive groups of an inactive community sorted by name
select is(
    list_community_groups(
        :'communityID'::uuid,
        '{"limit": 10, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'groups', jsonb_build_array(
            get_group_summary(:'communityID'::uuid, :'groupActiveID'::uuid)::jsonb,
            get_group_summary(:'communityID'::uuid, :'groupInactiveID'::uuid)::jsonb
        ),
        'total', 2
    ),
    'Should list active and inactive groups of an inactive community sorted by name'
);

-- Should paginate groups and count every match
select is(
    list_community_groups(
        :'communityID'::uuid,
        '{"limit": 1, "offset": 1}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'groups', jsonb_build_array(
            get_group_summary(:'communityID'::uuid, :'groupInactiveID'::uuid)::jsonb
        ),
        'total', 2
    ),
    'Should paginate groups and count every match'
);

-- Should return an empty page for an unknown community
select is(
    list_community_groups(
        :'unknownCommunityID'::uuid,
        '{"limit": 10, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'groups', '[]'::jsonb,
        'total', 0
    ),
    'Should return an empty page for an unknown community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
