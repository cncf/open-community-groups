-- Tests reading user notification preferences.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeGroupID '9e050000-0000-0000-0000-000000000001'
\set communityID '9e050000-0000-0000-0000-000000000002'
\set deletedGroupID '9e050000-0000-0000-0000-000000000003'
\set emptyUserID '9e050000-0000-0000-0000-000000000004'
\set groupCategoryID '9e050000-0000-0000-0000-000000000005'
\set inactiveCommunityGroupCategoryID '9e050000-0000-0000-0000-000000000006'
\set inactiveCommunityGroupID '9e050000-0000-0000-0000-000000000007'
\set inactiveCommunityID '9e050000-0000-0000-0000-000000000008'
\set inactiveGroupID '9e050000-0000-0000-0000-000000000009'
\set userID '9e050000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community containing most muted groups
select fx_community(:'communityID', jsonb_build_object('display_name', 'Active Community'));

-- Inactive community containing an unavailable muted group
select fx_community(:'inactiveCommunityID', jsonb_build_object(
    'active', false,
    'display_name', 'Inactive Community'
));

-- Group category for active-community groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category for inactive-community groups
select fx_group_category(:'inactiveCommunityGroupCategoryID', :'inactiveCommunityID');

-- User with no preferences
select fx_user(:'emptyUserID');

-- User with opt-outs and muted groups
select fx_user(:'userID');

-- Available muted group
select fx_group(:'activeGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', 'https://fixture.test/active.png',
    'name', 'Active Muted Group'
));

-- Deleted muted group listed as unavailable
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'deleted_at', '2024-01-01 00:00:00+00',
    'name', 'Deleted Muted Group'
));

-- Muted group in an inactive community listed as unavailable
select fx_group(:'inactiveCommunityGroupID', :'inactiveCommunityID', :'inactiveCommunityGroupCategoryID', jsonb_build_object(
    'name', 'Inactive Community Muted Group'
));

-- Inactive muted group listed as unavailable
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'name', 'Inactive Muted Group'
));

-- Opt-outs inserted out of order to prove sorted output
insert into user_notification_opt_out (notification_category_id, user_id)
values
    ('new-events', :'userID'),
    ('badges', :'userID');

-- Muted groups covering available and unavailable states
insert into user_group_notification_mute (group_id, user_id)
values
    (:'activeGroupID', :'userID'),
    (:'deletedGroupID', :'userID'),
    (:'inactiveCommunityGroupID', :'userID'),
    (:'inactiveGroupID', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return empty preferences for users without rows
select is(
    get_user_notification_preferences(:'emptyUserID')::jsonb,
    jsonb_build_object(
        'muted_groups', '[]'::jsonb,
        'opted_out_categories', '[]'::jsonb
    ),
    'Should return empty preferences for users without rows'
);

-- Should return opted-out categories sorted
select is(
    get_user_notification_preferences(:'userID')::jsonb->'opted_out_categories',
    jsonb_build_array('badges', 'new-events'),
    'Should return opted-out categories sorted'
);

-- Should list muted groups including unavailable groups
select is(
    (
        select jsonb_agg(group_data - 'muted_at' order by group_data->>'name')
        from jsonb_array_elements(get_user_notification_preferences(:'userID')::jsonb->'muted_groups') group_data
    ),
    jsonb_build_array(
        jsonb_build_object(
            'available', true,
            'community_display_name', 'Active Community',
            'group_id', :'activeGroupID'::uuid,
            'logo_url', 'https://fixture.test/active.png',
            'name', 'Active Muted Group'
        ),
        jsonb_build_object(
            'available', false,
            'community_display_name', 'Active Community',
            'group_id', :'deletedGroupID'::uuid,
            'name', 'Deleted Muted Group'
        ),
        jsonb_build_object(
            'available', false,
            'community_display_name', 'Inactive Community',
            'group_id', :'inactiveCommunityGroupID'::uuid,
            'name', 'Inactive Community Muted Group'
        ),
        jsonb_build_object(
            'available', false,
            'community_display_name', 'Active Community',
            'group_id', :'inactiveGroupID'::uuid,
            'name', 'Inactive Muted Group'
        )
    ),
    'Should list muted groups including unavailable groups'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
