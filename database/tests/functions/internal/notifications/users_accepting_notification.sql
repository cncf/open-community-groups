-- Tests notification preference acceptance rules.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeGroupID '9e010000-0000-0000-0000-000000000001'
\set categoryOptOutUserID '9e010000-0000-0000-0000-000000000002'
\set communityID '9e010000-0000-0000-0000-000000000003'
\set deletedGroupID '9e010000-0000-0000-0000-000000000004'
\set enabledUserID '9e010000-0000-0000-0000-000000000005'
\set groupCategoryID '9e010000-0000-0000-0000-000000000006'
\set inactiveGroupID '9e010000-0000-0000-0000-000000000007'
\set mutableMuteUserID '9e010000-0000-0000-0000-000000000008'
\set otherGroupID '9e010000-0000-0000-0000-000000000009'
\set otherUserID '9e010000-0000-0000-0000-000000000010'
\set removedMuteOptOutUserID '9e010000-0000-0000-0000-000000000011'
\set teamMuteUserID '9e010000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing groups used by mute scenarios
select fx_community(:'communityID');

-- Group category containing groups used by mute scenarios
select fx_group_category(:'groupCategoryID', :'communityID');

-- User with no preference rows
select fx_user(:'enabledUserID');

-- User opted out of a mutable category
select fx_user(:'categoryOptOutUserID');

-- User muted against group-mutable categories
select fx_user(:'mutableMuteUserID');

-- User whose rows must not affect another user
select fx_user(:'otherUserID');

-- User with a muted group and a team-category opt-out test
select fx_user(:'teamMuteUserID');

-- User representing a prior unmute while the category opt-out remains
select fx_user(:'removedMuteOptOutUserID');

-- Active group used by mutes and notification scope
select fx_group(:'activeGroupID', :'communityID', :'groupCategoryID');

-- Deleted group whose mute should still apply
select fx_group(
    :'deletedGroupID',
    :'communityID',
    :'groupCategoryID',
    jsonb_build_object(
        'active', false,
        'deleted', true,
        'deleted_at', '2024-01-01 00:00:00+00'
    )
);

-- Inactive group whose mute should still apply
select fx_group(
    :'inactiveGroupID',
    :'communityID',
    :'groupCategoryID',
    jsonb_build_object('active', false)
);

-- Unmuted group used by unrelated group-scope checks
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Category opt-out for mutable event publication notifications
insert into user_notification_opt_out (notification_category_id, user_id)
values ('new-events', :'categoryOptOutUserID');

-- Category opt-out that should still apply when no mute is present
insert into user_notification_opt_out (notification_category_id, user_id)
values ('new-events', :'removedMuteOptOutUserID');

-- Opt-out on another user that must not affect the enabled user
insert into user_notification_opt_out (notification_category_id, user_id)
values ('new-events', :'otherUserID');

-- Mute for group-mutable notification filtering
insert into user_group_notification_mute (group_id, user_id)
values (:'activeGroupID', :'mutableMuteUserID');

-- Mute on a deleted group that should still apply
insert into user_group_notification_mute (group_id, user_id)
values (:'deletedGroupID', :'mutableMuteUserID');

-- Mute on an inactive group that should still apply
insert into user_group_notification_mute (group_id, user_id)
values (:'inactiveGroupID', :'mutableMuteUserID');

-- Mute that should not affect team categories
insert into user_group_notification_mute (group_id, user_id)
values (:'activeGroupID', :'teamMuteUserID');

-- Mute on another user that must not affect the enabled user
insert into user_group_notification_mute (group_id, user_id)
values (:'activeGroupID', :'otherUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep the properties the planner needs to inline the helper
select is(
    (
        select
            l.lanname = 'sql'
            and p.proconfig is null
            and not p.proisstrict
            and p.proretset
            and not p.prosecdef
            and p.provolatile = 's'
        from pg_proc p
        join pg_language l on l.oid = p.prolang
        where p.proname = 'users_accepting_notification'
    ),
    true,
    'Should keep the properties the planner needs to inline the helper'
);

-- Should accept always-sent kinds despite other preferences
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-refund-requested',
            array[:'categoryOptOutUserID']::uuid[],
            array[:'activeGroupID']::uuid[]
        )
    ),
    array[:'categoryOptOutUserID']::uuid[],
    'Should accept always-sent kinds despite other preferences'
);

-- Should accept mutable categories with empty group lists when the category is enabled
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-published',
            array[:'enabledUserID']::uuid[],
            '{}'::uuid[]
        )
    ),
    array[:'enabledUserID']::uuid[],
    'Should accept mutable categories with empty group lists when the category is enabled'
);

-- Should accept mutable categories with null group lists when the category is enabled
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-published',
            array[:'enabledUserID']::uuid[],
            null::uuid[]
        )
    ),
    array[:'enabledUserID']::uuid[],
    'Should accept mutable categories with null group lists when the category is enabled'
);

-- Should accept team categories despite muted groups
select is(
    array(
        select user_id
        from users_accepting_notification(
            'inbox-message-received',
            array[:'teamMuteUserID']::uuid[],
            array[:'activeGroupID']::uuid[]
        )
    ),
    array[:'teamMuteUserID']::uuid[],
    'Should accept team categories despite muted groups'
);

-- Should ignore other users preference rows
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-published',
            array[:'enabledUserID']::uuid[],
            array[:'activeGroupID']::uuid[]
        )
    ),
    array[:'enabledUserID']::uuid[],
    'Should ignore other users preference rows'
);

-- Should reject opted-out categories
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-published',
            array[:'categoryOptOutUserID']::uuid[],
            array[:'activeGroupID']::uuid[]
        )
    ),
    '{}'::uuid[],
    'Should reject opted-out categories'
);

-- Should reject muted deleted groups
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-published',
            array[:'mutableMuteUserID']::uuid[],
            array[:'deletedGroupID']::uuid[]
        )
    ),
    '{}'::uuid[],
    'Should reject muted deleted groups'
);

-- Should reject muted groups in the notification scope
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-published',
            array[:'mutableMuteUserID']::uuid[],
            array[:'activeGroupID']::uuid[]
        )
    ),
    '{}'::uuid[],
    'Should reject muted groups in the notification scope'
);

-- Should reject muted inactive groups
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-published',
            array[:'mutableMuteUserID']::uuid[],
            array[:'inactiveGroupID']::uuid[]
        )
    ),
    '{}'::uuid[],
    'Should reject muted inactive groups'
);

-- Should reject opted-out categories even when no mute remains
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-published',
            array[:'removedMuteOptOutUserID']::uuid[],
            array[:'activeGroupID']::uuid[]
        )
    ),
    '{}'::uuid[],
    'Should reject opted-out categories even when no mute remains'
);

-- Should ignore muted groups outside the notification scope
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-published',
            array[:'mutableMuteUserID']::uuid[],
            array[:'otherGroupID']::uuid[]
        )
    ),
    array[:'mutableMuteUserID']::uuid[],
    'Should ignore muted groups outside the notification scope'
);

-- Should return accepted users with their input positions
select is(
    array(
        select ordinal || ':' || user_id
        from users_accepting_notification(
            'event-published',
            array[
                :'teamMuteUserID',
                :'categoryOptOutUserID',
                :'enabledUserID',
                :'mutableMuteUserID',
                :'teamMuteUserID'
            ]::uuid[],
            array[:'otherGroupID']::uuid[]
        )
        order by ordinal
    ),
    array[
        '1:' || :'teamMuteUserID',
        '3:' || :'enabledUserID',
        '4:' || :'mutableMuteUserID',
        '5:' || :'teamMuteUserID'
    ],
    'Should return accepted users with their input positions'
);

-- Should return no users for null recipient lists
select is(
    array(
        select user_id
        from users_accepting_notification(
            'event-published',
            null::uuid[],
            array[:'activeGroupID']::uuid[]
        )
    ),
    '{}'::uuid[],
    'Should return no users for null recipient lists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
