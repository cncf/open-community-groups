-- Tests seeding the event surveys category from event reminders opt-outs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set bothOptedOutUserID '94000000-0000-0000-0000-000000000003'
\set noOptOutsUserID '94000000-0000-0000-0000-000000000004'
\set otherOptedOutUserID '94000000-0000-0000-0000-000000000002'
\set remindersOptedOutUserID '94000000-0000-0000-0000-000000000001'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep event surveys on for users who turned another category off
select results_eq(
    format(
        $$
            select notification_category_id
            from user_notification_opt_out
            where user_id = %L::uuid
            order by notification_category_id
        $$,
        :'otherOptedOutUserID'
    ),
    $$ values ('badges'::text) $$,
    'Should keep event surveys on for users who turned another category off'
);

-- Should keep event surveys on for users without opt-outs
select is_empty(
    format(
        $$
            select notification_category_id
            from user_notification_opt_out
            where user_id = %L::uuid
        $$,
        :'noOptOutsUserID'
    ),
    'Should keep event surveys on for users without opt-outs'
);

-- Should turn event surveys off for users who turned event reminders and another category off
select results_eq(
    format(
        $$
            select notification_category_id
            from user_notification_opt_out
            where user_id = %L::uuid
            order by notification_category_id
        $$,
        :'bothOptedOutUserID'
    ),
    $$ values
        ('badges'::text),
        ('event-reminders'::text),
        ('event-surveys'::text)
    $$,
    'Should turn event surveys off for users who turned event reminders and another category off'
);

-- Should turn event surveys off for users who turned only event reminders off
select results_eq(
    format(
        $$
            select notification_category_id
            from user_notification_opt_out
            where user_id = %L::uuid
            order by notification_category_id
        $$,
        :'remindersOptedOutUserID'
    ),
    $$ values
        ('event-reminders'::text),
        ('event-surveys'::text)
    $$,
    'Should turn event surveys off for users who turned only event reminders off'
);

-- Should keep event reminders off when event surveys are turned back on
select lives_ok(
    format(
        $$select update_user_notification_preferences(%L::uuid, '{"event-surveys": true}'::jsonb)$$,
        :'remindersOptedOutUserID'
    ),
    'Should turn event surveys back on'
);
select results_eq(
    format(
        $$
            select notification_category_id
            from user_notification_opt_out
            where user_id = %L::uuid
            order by notification_category_id
        $$,
        :'remindersOptedOutUserID'
    ),
    $$ values ('event-reminders'::text) $$,
    'Should keep event reminders off when event surveys are turned back on'
);

-- Should keep event surveys on when event reminders are turned off later
select lives_ok(
    format(
        $$select update_user_notification_preferences(%L::uuid, '{"event-reminders": false}'::jsonb)$$,
        :'otherOptedOutUserID'
    ),
    'Should turn event reminders off'
);
select results_eq(
    format(
        $$
            select notification_category_id
            from user_notification_opt_out
            where user_id = %L::uuid
            order by notification_category_id
        $$,
        :'otherOptedOutUserID'
    ),
    $$ values
        ('badges'::text),
        ('event-reminders'::text)
    $$,
    'Should keep event surveys on when event reminders are turned off later'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
