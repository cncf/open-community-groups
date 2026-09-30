-- Tests updating user notification category preferences.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userID '9e070000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User whose preferences are updated
select fx_user(:'userID');

-- Existing opt-outs used to prove partial updates and true-value deletion
insert into user_notification_opt_out (notification_category_id, user_id)
values
    ('badges', :'userID'),
    ('event-reminders', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should partially update submitted categories
select lives_ok(
    format(
        $$
            select update_user_notification_preferences(
                %L::uuid,
                '{"badges": true, "new-events": false}'::jsonb
            )
        $$,
        :'userID'
    ),
    'Should partially update submitted categories'
);

-- Should preserve unsubmitted categories, delete true values, and insert false values
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
        ('event-reminders'::text),
        ('new-events'::text)
    $$,
    'Should preserve unsubmitted categories, delete true values, and insert false values'
);

-- Should keep false values idempotent
select lives_ok(
    format(
        $$
            select update_user_notification_preferences(
                %L::uuid,
                '{"new-events": false}'::jsonb
            )
        $$,
        :'userID'
    ),
    'Should keep false values idempotent'
);

-- Should audit the resulting opted-out categories after each save
select results_eq(
    format(
        $$
            select action, details
            from audit_log
            where actor_user_id = %L::uuid
            and action = 'user_notification_preferences_updated'
            order by created_at desc, audit_log_id desc
            limit 1
        $$,
        :'userID'
    ),
    $$ values (
        'user_notification_preferences_updated'::text,
        '{"opted_out_categories":["event-reminders","new-events"]}'::jsonb
    ) $$,
    'Should audit the resulting opted-out categories after each save'
);

-- Should reject non-boolean values
select throws_ok(
    format(
        $$
            select update_user_notification_preferences(
                %L::uuid,
                '{"badges": "yes"}'::jsonb
            )
        $$,
        :'userID'
    ),
    'OCG01',
    'invalid notification preferences',
    'Should reject non-boolean values'
);

-- Should reject unknown categories
select throws_ok(
    format(
        $$
            select update_user_notification_preferences(
                %L::uuid,
                '{"unknown": false}'::jsonb
            )
        $$,
        :'userID'
    ),
    'OCG01',
    'unknown notification category',
    'Should reject unknown categories'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
