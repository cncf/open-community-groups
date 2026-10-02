-- Tests user group notification mute constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c0060000-0000-0000-0000-000000000001'
\set duplicateGroupID 'c0060000-0000-0000-0000-000000000002'
\set duplicateUserID 'c0060000-0000-0000-0000-000000000003'
\set groupCascadeGroupID 'c0060000-0000-0000-0000-000000000004'
\set groupCascadeUserID 'c0060000-0000-0000-0000-000000000005'
\set groupCategoryID 'c0060000-0000-0000-0000-000000000006'
\set missingGroupID 'c0060000-0000-0000-0000-000000000007'
\set missingUserID 'c0060000-0000-0000-0000-000000000008'
\set userCascadeGroupID 'c0060000-0000-0000-0000-000000000009'
\set userCascadeUserID 'c0060000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing groups muted by the constraint scenarios
select fx_community(:'communityID');

-- Group category containing groups muted by the constraint scenarios
select fx_group_category(:'groupCategoryID', :'communityID');

-- User whose mute is duplicated
select fx_user(:'duplicateUserID');

-- User whose mute is deleted through group cascade
select fx_user(:'groupCascadeUserID');

-- User whose mute is deleted through user cascade
select fx_user(:'userCascadeUserID');

-- Group whose mute is duplicated
select fx_group(:'duplicateGroupID', :'communityID', :'groupCategoryID');

-- Group whose mute is deleted through group cascade
select fx_group(:'groupCascadeGroupID', :'communityID', :'groupCategoryID');

-- Group whose mute is deleted through user cascade
select fx_group(:'userCascadeGroupID', :'communityID', :'groupCategoryID');

-- Mute used by duplicate rejection
insert into user_group_notification_mute (group_id, user_id)
values (:'duplicateGroupID', :'duplicateUserID');

-- Mute deleted through group cascade
insert into user_group_notification_mute (group_id, user_id)
values (:'groupCascadeGroupID', :'groupCascadeUserID');

-- Mute deleted through user cascade
insert into user_group_notification_mute (group_id, user_id)
values (:'userCascadeGroupID', :'userCascadeUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject duplicate mutes
select throws_ok(
    format(
        $$
            insert into user_group_notification_mute (group_id, user_id)
            values (%L::uuid, %L::uuid)
        $$,
        :'duplicateGroupID',
        :'duplicateUserID'
    ),
    '23505',
    null,
    'Should reject duplicate mutes'
);

-- Should reject mutes for missing groups
select throws_ok(
    format(
        $$
            insert into user_group_notification_mute (group_id, user_id)
            values (%L::uuid, %L::uuid)
        $$,
        :'missingGroupID',
        :'duplicateUserID'
    ),
    '23503',
    null,
    'Should reject mutes for missing groups'
);

-- Should reject mutes for missing users
select throws_ok(
    format(
        $$
            insert into user_group_notification_mute (group_id, user_id)
            values (%L::uuid, %L::uuid)
        $$,
        :'duplicateGroupID',
        :'missingUserID'
    ),
    '23503',
    null,
    'Should reject mutes for missing users'
);

-- Should delete mutes when groups are deleted
select lives_ok(
    format($$delete from "group" where group_id = %L::uuid$$, :'groupCascadeGroupID'),
    'Should delete groups with mutes'
);
select is(
    (
        select count(*)::int
        from user_group_notification_mute
        where group_id = :'groupCascadeGroupID'
    ),
    0,
    'Should delete mutes when groups are deleted'
);

-- Should delete mutes when users are deleted
select lives_ok(
    format($$delete from "user" where user_id = %L::uuid$$, :'userCascadeUserID'),
    'Should delete users with mutes'
);
select is(
    (
        select count(*)::int
        from user_group_notification_mute
        where user_id = :'userCascadeUserID'
    ),
    0,
    'Should delete mutes when users are deleted'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
