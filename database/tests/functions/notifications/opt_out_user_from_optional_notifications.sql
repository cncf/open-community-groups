-- Tests opting a user out of optional notifications from SMTP suppression lists.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userID '9e040000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User resolved by the suppression helper
select fx_user(:'userID', jsonb_build_object(
    'email', 'Suppressed.User@example.test',
    'username', 'suppressed-user'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should opt out every category for a case-insensitive email match
select is(
    opt_out_user_from_optional_notifications(
        'suppressed.user@EXAMPLE.test',
        'smtp bounce'
    ),
    9,
    'Should opt out every category for a case-insensitive email match'
);

-- Should persist every notification category opt-out
select results_eq(
    format(
        $$
            select notification_category_id
            from user_notification_opt_out
            where user_id = %L::uuid
            order by notification_category_id
        $$,
        :'userID'
    ),
    $$ values
        ('attendee-activity'::text),
        ('badges'::text),
        ('cohosting-updates'::text),
        ('event-reminders'::text),
        ('group-announcements'::text),
        ('group-inbox'::text),
        ('new-events'::text),
        ('organizer-messages'::text),
        ('paid-event-setups'::text)
    $$,
    'Should persist every notification category opt-out'
);

-- Should audit the suppression reason, database user, and category ids
select ok(
    (
        select details = jsonb_build_object(
            'database_user', current_user,
            'notification_category_ids', jsonb_build_array(
                'attendee-activity',
                'badges',
                'cohosting-updates',
                'event-reminders',
                'group-announcements',
                'group-inbox',
                'new-events',
                'organizer-messages',
                'paid-event-setups'
            ),
            'reason', 'smtp bounce'
        )
        from audit_log
        where action = 'user_notifications_suppressed'
        and resource_id = :'userID'
        and resource_type = 'user'
    ),
    'Should audit the suppression reason, database user, and category ids'
);

-- Should return zero and skip audit when rerun
select is(
    opt_out_user_from_optional_notifications(
        'suppressed.user@example.test',
        'smtp bounce'
    ),
    0,
    'Should return zero and skip audit when rerun'
);
select is(
    (
        select count(*)::int
        from audit_log
        where action = 'user_notifications_suppressed'
        and resource_id = :'userID'
    ),
    1,
    'Should skip audit when rerun'
);

-- Should reject blank emails
select throws_ok(
    $$select opt_out_user_from_optional_notifications(' ', 'smtp bounce')$$,
    'email is required',
    'Should reject blank emails'
);

-- Should reject blank reasons
select throws_ok(
    $$select opt_out_user_from_optional_notifications('suppressed.user@example.test', ' ')$$,
    'suppression reason is required',
    'Should reject blank reasons'
);

-- Should reject unknown emails
select throws_ok(
    $$select opt_out_user_from_optional_notifications('missing@example.test', 'smtp bounce')$$,
    'user not found',
    'Should reject unknown emails'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
