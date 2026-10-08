-- Tests summarizing the community contact recipients.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adminUserID '8a0f0000-0000-0000-0000-000000000011'
\set alphaGroupID '8a0f0000-0000-0000-0000-000000000007'
\set bravoGroupID '8a0f0000-0000-0000-0000-000000000008'
\set charlieGroupID '8a0f0000-0000-0000-0000-000000000009'
\set communityID '8a0f0000-0000-0000-0000-000000000001'
\set foreignCategoryID '8a0f0000-0000-0000-0000-000000000005'
\set foreignCommunityID '8a0f0000-0000-0000-0000-000000000002'
\set northRegionID '8a0f0000-0000-0000-0000-000000000006'
\set platformCategoryID '8a0f0000-0000-0000-0000-000000000003'
\set runtimeCategoryID '8a0f0000-0000-0000-0000-000000000004'
\set viewerUserID '8a0f0000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose recipients are summarized
select fx_community(:'communityID');

-- Community owning the foreign group category
select fx_community(:'foreignCommunityID');

-- Admin of the alpha and bravo groups
select fx_user(:'adminUserID');

-- Viewer of the bravo group
select fx_user(:'viewerUserID');

-- Group category of the foreign community
select fx_group_category(:'foreignCategoryID', :'foreignCommunityID');

-- Platform group category
select fx_group_category(:'platformCategoryID', :'communityID', jsonb_build_object('name', 'Platform'));

-- Runtime group category
select fx_group_category(:'runtimeCategoryID', :'communityID', jsonb_build_object('name', 'Runtime'));

-- North region
insert into region (region_id, community_id, name)
values (:'northRegionID', :'communityID', 'North');

-- Runtime group without region
select fx_group(:'alphaGroupID', :'communityID', :'runtimeCategoryID', jsonb_build_object('name', 'Alpha'));

-- Platform group in the north region
select fx_group(
    :'bravoGroupID',
    :'communityID',
    :'platformCategoryID',
    jsonb_build_object('name', 'Bravo', 'region_id', :'northRegionID')
);

-- Platform group without team seats
select fx_group(:'charlieGroupID', :'communityID', :'platformCategoryID', jsonb_build_object('name', 'Charlie'));

-- Team seats, including one person on two groups
insert into group_team (group_id, user_id, accepted, role) values
    (:'alphaGroupID', :'adminUserID', true, 'admin'),
    (:'bravoGroupID', :'adminUserID', true, 'admin'),
    (:'bravoGroupID', :'viewerUserID', true, 'viewer');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should apply the filters to the summary
select is(
    get_community_contact_recipients_summary(:'communityID'::uuid, '{"roles": ["viewer"]}'::jsonb)::jsonb,
    jsonb_build_object(
        'groups', jsonb_build_array(
            jsonb_build_object(
                'group_category_name', 'Platform',
                'group_id', :'bravoGroupID',
                'name', 'Bravo',
                'seats_count', 1,

                'region_name', 'North'
            )
        ),
        'groups_count', 1,
        'people_count', 1,
        'seats_count', 1
    ),
    'Should apply the filters to the summary'
);

-- Should count distinct people, seats and contributing groups
select is(
    get_community_contact_recipients_summary(:'communityID'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object(
        'groups', jsonb_build_array(
            jsonb_build_object(
                'group_category_name', 'Runtime',
                'group_id', :'alphaGroupID',
                'name', 'Alpha',
                'seats_count', 1
            ),
            jsonb_build_object(
                'group_category_name', 'Platform',
                'group_id', :'bravoGroupID',
                'name', 'Bravo',
                'seats_count', 2,

                'region_name', 'North'
            )
        ),
        'groups_count', 2,
        'people_count', 2,
        'seats_count', 3
    ),
    'Should count distinct people, seats and contributing groups'
);

-- Should reject filters outside the community
select throws_ok(
    format(
        $$select get_community_contact_recipients_summary(
            %L::uuid,
            jsonb_build_object('group_category_ids', jsonb_build_array(%L))
        )$$,
        :'communityID',
        :'foreignCategoryID'
    ),
    'OCG01',
    'group category not found',
    'Should reject filters outside the community'
);

-- Should return an empty summary when no seats match
select is(
    get_community_contact_recipients_summary(
        :'communityID'::uuid,
        '{"roles": ["check-in-manager"]}'::jsonb
    )::jsonb,
    '{"groups": [], "groups_count": 0, "people_count": 0, "seats_count": 0}'::jsonb,
    'Should return an empty summary when no seats match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
