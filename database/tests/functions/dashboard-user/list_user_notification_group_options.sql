-- Tests listing user notification group mute options.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set availableGroupID '9e060000-0000-0000-0000-000000000001'
\set communityID '9e060000-0000-0000-0000-000000000002'
\set groupCategoryID '9e060000-0000-0000-0000-000000000003'
\set mutedGroupID '9e060000-0000-0000-0000-000000000004'
\set userID '9e060000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing connected groups
select fx_community(:'communityID', jsonb_build_object('display_name', 'Notification Options Community'));

-- Group category containing connected groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- User connected to both groups
select fx_user(:'userID');

-- Connected group returned by the options list
select fx_group(:'availableGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', 'https://fixture.test/available.png',
    'name', 'Available Group'
));

-- Connected group excluded because it is already muted
select fx_group(:'mutedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Muted Group'
));

-- Membership connecting the user to the available group
insert into group_member (group_id, user_id)
values (:'availableGroupID', :'userID');

-- Membership connecting the user to the muted group
insert into group_member (group_id, user_id)
values (:'mutedGroupID', :'userID');

-- Existing mute excluded from the option list
insert into user_group_notification_mute (group_id, user_id)
values (:'mutedGroupID', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list connected groups excluding already-muted groups
select is(
    list_user_notification_group_options(:'userID')::jsonb,
    jsonb_build_array(jsonb_build_object(
        'community_display_name', 'Notification Options Community',
        'group_id', :'availableGroupID'::uuid,
        'logo_url', 'https://fixture.test/available.png',
        'name', 'Available Group'
    )),
    'Should list connected groups excluding already-muted groups'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
