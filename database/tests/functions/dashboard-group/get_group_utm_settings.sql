-- Tests retrieving the UTM values a group accepts for its event page views.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c0b30000-0000-0000-0000-000000000001'
\set groupCategoryID 'c0b30000-0000-0000-0000-000000000002'
\set groupDeletedID 'c0b30000-0000-0000-0000-000000000005'
\set groupID 'c0b30000-0000-0000-0000-000000000003'
\set groupWithoutUtmID 'c0b30000-0000-0000-0000-000000000004'
\set otherCommunityID 'c0b30000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the groups
select fx_community(:'communityID');

-- Community the groups do not belong to
select fx_community(:'otherCommunityID');

-- Group category used by the groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group accepting its own UTM values
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'utm_campaigns', jsonb_build_array('spring-launch'),
    'utm_mediums', jsonb_build_array('podcast'),
    'utm_sources', jsonb_build_array('newsletter', 'partner.site')
));

-- Deleted group that still holds UTM values
select fx_group(:'groupDeletedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'utm_sources', jsonb_build_array('newsletter')
));

-- Group without UTM values
select fx_group(:'groupWithoutUtmID', :'communityID', :'groupCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return empty lists for a group without UTM values
select is(
    get_group_utm_settings(:'communityID'::uuid, :'groupWithoutUtmID'::uuid)::jsonb,
    jsonb_build_object(
        'campaigns', jsonb_build_array(),
        'mediums', jsonb_build_array(),
        'sources', jsonb_build_array()
    ),
    'Should return empty lists for a group without UTM values'
);

-- Should return no settings for a deleted group
select is(
    get_group_utm_settings(:'communityID'::uuid, :'groupDeletedID'::uuid)::jsonb,
    null::jsonb,
    'Should return no settings for a deleted group'
);

-- Should return no settings for a group outside the community
select is(
    get_group_utm_settings(:'otherCommunityID'::uuid, :'groupID'::uuid)::jsonb,
    null::jsonb,
    'Should return no settings for a group outside the community'
);

-- Should return the UTM values accepted by the group
select is(
    get_group_utm_settings(:'communityID'::uuid, :'groupID'::uuid)::jsonb,
    jsonb_build_object(
        'campaigns', jsonb_build_array('spring-launch'),
        'mediums', jsonb_build_array('podcast'),
        'sources', jsonb_build_array('newsletter', 'partner.site')
    ),
    'Should return the UTM values accepted by the group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
