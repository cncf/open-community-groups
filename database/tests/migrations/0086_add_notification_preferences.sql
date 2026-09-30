-- Tests upgrading notification preference flags into category opt-outs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

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

-- Should assign notification kinds to categories
select results_eq(
    $$
        select name, notification_category_id
        from notification_kind
        where notification_category_id is not null
        order by name
    $$,
    $$ values
        ('badge-awarded', 'badges'::text),
        ('badge-revoked', 'badges'::text),
        ('event-admission-offer-declined', 'attendee-activity'::text),
        ('event-cohost-removed', 'cohosting-updates'::text),
        ('event-cohost-responded', 'cohosting-updates'::text),
        ('event-custom', 'organizer-messages'::text),
        ('event-paid-configured', 'paid-event-setups'::text),
        ('event-published', 'new-events'::text),
        ('event-reminder', 'event-reminders'::text),
        ('event-series-published', 'new-events'::text),
        ('group-custom', 'group-announcements'::text),
        ('inbox-message-received', 'group-inbox'::text)
    $$,
    'Should assign notification kinds to categories'
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
