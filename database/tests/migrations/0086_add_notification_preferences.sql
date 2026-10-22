-- Tests upgrading notification preference flags into category opt-outs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set falseUserID '86000000-0000-0000-0000-000000000001'
\set notificationID '86000000-0000-0000-0000-000000000003'
\set trueUserID '86000000-0000-0000-0000-000000000002'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should drop the replaced user flag
select hasnt_column('user', 'optional_notifications_enabled');

-- Should drop the replaced notification kind flag
select hasnt_column('notification_kind', 'optional_notification');

-- Should create opt-outs for users who disabled optional notifications
select results_eq(
    format(
        $$
            select notification_category_id
            from user_notification_opt_out
            where user_id = %L::uuid
            order by notification_category_id
        $$,
        :'falseUserID'
    ),
    $$ values
        ('event-reminders'::text),
        ('event-surveys'::text),
        ('group-announcements'::text),
        ('new-events'::text),
        ('organizer-messages'::text)
    $$,
    'Should create opt-outs for users who disabled optional notifications'
);

-- Should not create opt-outs for users who kept optional notifications enabled
select is(
    (
        select count(*)::int
        from user_notification_opt_out
        where user_id = :'trueUserID'
    ),
    0,
    'Should not create opt-outs for users who kept optional notifications enabled'
);

-- Should not create group mutes during migration
select is(
    (select count(*)::int from user_group_notification_mute),
    0,
    'Should not create group mutes during migration'
);

-- Should preserve existing users
select is(
    (
        select count(*)::int
        from "user"
        where user_id in (:'falseUserID', :'trueUserID')
    ),
    2,
    'Should preserve existing users'
);

-- Should preserve existing notifications
select results_eq(
    format(
        $$
            select kind, user_id
            from notification
            where notification_id = %L::uuid
        $$,
        :'notificationID'
    ),
    format($$ values ('event-canceled'::text, %L::uuid) $$, :'falseUserID'),
    'Should preserve existing notifications'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
