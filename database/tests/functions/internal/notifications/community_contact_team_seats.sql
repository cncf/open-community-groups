-- Tests matching community group team seats against contact filters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adminUserID '8a0c0000-0000-0000-0000-000000000021'
\set categoryAID '8a0c0000-0000-0000-0000-000000000002'
\set categoryBID '8a0c0000-0000-0000-0000-000000000003'
\set communityID '8a0c0000-0000-0000-0000-000000000001'
\set deletedGroupID '8a0c0000-0000-0000-0000-000000000016'
\set deletedGroupUserID '8a0c0000-0000-0000-0000-000000000029'
\set foreignCategoryID '8a0c0000-0000-0000-0000-000000000005'
\set foreignCommunityID '8a0c0000-0000-0000-0000-000000000004'
\set foreignGroupID '8a0c0000-0000-0000-0000-000000000017'
\set foreignUserID '8a0c0000-0000-0000-0000-000000000030'
\set groupAID '8a0c0000-0000-0000-0000-000000000011'
\set groupBID '8a0c0000-0000-0000-0000-000000000012'
\set inactiveGroupID '8a0c0000-0000-0000-0000-000000000015'
\set inactiveGroupUserID '8a0c0000-0000-0000-0000-000000000028'
\set mixedUserID '8a0c0000-0000-0000-0000-000000000022'
\set noRegionGroupID '8a0c0000-0000-0000-0000-000000000013'
\set noRegionUserID '8a0c0000-0000-0000-0000-000000000024'
\set northRegionID '8a0c0000-0000-0000-0000-000000000006'
\set pendingUserID '8a0c0000-0000-0000-0000-000000000026'
\set southRegionID '8a0c0000-0000-0000-0000-000000000007'
\set subgroupID '8a0c0000-0000-0000-0000-000000000014'
\set subgroupUserID '8a0c0000-0000-0000-0000-000000000025'
\set unverifiedUserID '8a0c0000-0000-0000-0000-000000000027'
\set viewerUserID '8a0c0000-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose group team seats are matched
select fx_community(:'communityID');

-- Community whose seats are never matched
select fx_community(:'foreignCommunityID');

-- Admin of group A
select fx_user(:'adminUserID');

-- Admin of the deleted group
select fx_user(:'deletedGroupUserID');

-- Admin of the foreign community group
select fx_user(:'foreignUserID');

-- Admin of the inactive group
select fx_user(:'inactiveGroupUserID');

-- Viewer of group A and admin of group B
select fx_user(:'mixedUserID');

-- Events manager of the group without region
select fx_user(:'noRegionUserID');

-- Admin of group A who has not accepted the invitation
select fx_user(:'pendingUserID');

-- Check-in manager of the subgroup
select fx_user(:'subgroupUserID');

-- Admin of group A without a verified email
select fx_user(:'unverifiedUserID', jsonb_build_object('email_verified', false));

-- Viewer of group B
select fx_user(:'viewerUserID');

-- Group category A of the community
select fx_group_category(:'categoryAID', :'communityID');

-- Group category B of the community
select fx_group_category(:'categoryBID', :'communityID');

-- Group category of the foreign community
select fx_group_category(:'foreignCategoryID', :'foreignCommunityID');

-- North region of the community
insert into region (region_id, community_id, name)
values (:'northRegionID', :'communityID', 'North');

-- South region of the community
insert into region (region_id, community_id, name)
values (:'southRegionID', :'communityID', 'South');

-- Deleted group in category A and the north region
select fx_group(
    :'deletedGroupID',
    :'communityID',
    :'categoryAID',
    jsonb_build_object('active', false, 'deleted', true, 'region_id', :'northRegionID')
);

-- Group of the foreign community
select fx_group(:'foreignGroupID', :'foreignCommunityID', :'foreignCategoryID');

-- Active group A in category A and the north region
select fx_group(:'groupAID', :'communityID', :'categoryAID', jsonb_build_object('region_id', :'northRegionID'));

-- Active group B in category B and the south region
select fx_group(:'groupBID', :'communityID', :'categoryBID', jsonb_build_object('region_id', :'southRegionID'));

-- Inactive group in category A and the north region
select fx_group(
    :'inactiveGroupID',
    :'communityID',
    :'categoryAID',
    jsonb_build_object('active', false, 'region_id', :'northRegionID')
);

-- Active group in category A without region
select fx_group(:'noRegionGroupID', :'communityID', :'categoryAID');

-- Active subgroup of group A in category B and the north region
select fx_group(
    :'subgroupID',
    :'communityID',
    :'categoryBID',
    jsonb_build_object('parent_group_id', :'groupAID', 'region_id', :'northRegionID')
);

-- Team seats covering every eligibility and filter scenario
insert into group_team (group_id, user_id, accepted, role) values
    (:'deletedGroupID', :'deletedGroupUserID', true, 'admin'),
    (:'foreignGroupID', :'foreignUserID', true, 'admin'),
    (:'groupAID', :'adminUserID', true, 'admin'),
    (:'groupAID', :'mixedUserID', true, 'viewer'),
    (:'groupAID', :'pendingUserID', false, 'admin'),
    (:'groupAID', :'unverifiedUserID', true, 'admin'),
    (:'groupBID', :'mixedUserID', true, 'admin'),
    (:'groupBID', :'viewerUserID', true, 'viewer'),
    (:'inactiveGroupID', :'inactiveGroupUserID', true, 'admin'),
    (:'noRegionGroupID', :'noRegionUserID', true, 'events-manager'),
    (:'subgroupID', :'subgroupUserID', true, 'check-in-manager');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should apply all filters to the same seat
select results_eq(
    format(
        $$
            select group_id, user_id
            from community_contact_team_seats(
                %L::uuid,
                jsonb_build_object('group_category_ids', jsonb_build_array(%L), 'roles', jsonb_build_array('admin'))
            )
            order by group_id, user_id
        $$,
        :'communityID',
        :'categoryAID'
    ),
    format(
        $$ values (%L::uuid, %L::uuid) $$,
        :'groupAID',
        :'adminUserID'
    ),
    'Should apply all filters to the same seat'
);

-- Should filter by group category
select results_eq(
    format(
        $$
            select group_id, user_id
            from community_contact_team_seats(
                %L::uuid,
                jsonb_build_object('group_category_ids', jsonb_build_array(%L))
            )
            order by group_id, user_id
        $$,
        :'communityID',
        :'categoryBID'
    ),
    format(
        $$ values
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid)
        $$,
        :'groupBID', :'mixedUserID',
        :'groupBID', :'viewerUserID',
        :'subgroupID', :'subgroupUserID'
    ),
    'Should filter by group category'
);

-- Should filter by group role
select results_eq(
    format(
        $$
            select group_id, user_id
            from community_contact_team_seats(
                %L::uuid,
                '{"roles": ["check-in-manager", "viewer"]}'::jsonb
            )
            order by group_id, user_id
        $$,
        :'communityID'
    ),
    format(
        $$ values
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid)
        $$,
        :'groupAID', :'mixedUserID',
        :'groupBID', :'viewerUserID',
        :'subgroupID', :'subgroupUserID'
    ),
    'Should filter by group role'
);

-- Should filter by no region only
select results_eq(
    format(
        $$
            select group_id, user_id
            from community_contact_team_seats(%L::uuid, '{"regions": ["none"]}'::jsonb)
            order by group_id, user_id
        $$,
        :'communityID'
    ),
    format(
        $$ values (%L::uuid, %L::uuid) $$,
        :'noRegionGroupID',
        :'noRegionUserID'
    ),
    'Should filter by no region only'
);

-- Should filter by region
select results_eq(
    format(
        $$
            select group_id, user_id
            from community_contact_team_seats(
                %L::uuid,
                jsonb_build_object('regions', jsonb_build_array(%L))
            )
            order by group_id, user_id
        $$,
        :'communityID',
        :'northRegionID'
    ),
    format(
        $$ values
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid)
        $$,
        :'groupAID', :'adminUserID',
        :'groupAID', :'mixedUserID',
        :'subgroupID', :'subgroupUserID'
    ),
    'Should filter by region'
);

-- Should filter by regions and no region
select results_eq(
    format(
        $$
            select group_id, user_id
            from community_contact_team_seats(
                %L::uuid,
                jsonb_build_object('regions', jsonb_build_array(%L, 'none'))
            )
            order by group_id, user_id
        $$,
        :'communityID',
        :'southRegionID'
    ),
    format(
        $$ values
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid)
        $$,
        :'groupBID', :'mixedUserID',
        :'groupBID', :'viewerUserID',
        :'noRegionGroupID', :'noRegionUserID'
    ),
    'Should filter by regions and no region'
);

-- Should return every accepted and verified seat of available groups for missing filters
select results_eq(
    format(
        $$
            select group_id, user_id
            from community_contact_team_seats(%L::uuid, '{}'::jsonb)
            order by group_id, user_id
        $$,
        :'communityID'
    ),
    format(
        $$ values
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid)
        $$,
        :'groupAID', :'adminUserID',
        :'groupAID', :'mixedUserID',
        :'groupBID', :'mixedUserID',
        :'groupBID', :'viewerUserID',
        :'noRegionGroupID', :'noRegionUserID',
        :'subgroupID', :'subgroupUserID'
    ),
    'Should return every accepted and verified seat of available groups for missing filters'
);

-- Should treat empty filter lists as all values
select results_eq(
    format(
        $$
            select group_id, user_id
            from community_contact_team_seats(
                %L::uuid,
                '{"group_category_ids": [], "regions": [], "roles": []}'::jsonb
            )
            order by group_id, user_id
        $$,
        :'communityID'
    ),
    format(
        $$ values
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid)
        $$,
        :'groupAID', :'adminUserID',
        :'groupAID', :'mixedUserID',
        :'groupBID', :'mixedUserID',
        :'groupBID', :'viewerUserID',
        :'noRegionGroupID', :'noRegionUserID',
        :'subgroupID', :'subgroupUserID'
    ),
    'Should treat empty filter lists as all values'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
