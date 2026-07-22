-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationFailedID '8a080000-0000-0000-0000-000000000001'
\set notificationProcessedID '8a080000-0000-0000-0000-000000000002'
\set notificationUnknownID '8a080000-0000-0000-0000-000000000003'
\set userID '8a080000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'user@example.com', true, 'user');

-- Notifications
insert into notification (
    delivery_attempts,
    delivery_claimed_at,
    delivery_status,
    error,
    kind,
    notification_id,
    processed_at,
    user_id
) values
    (
        4,
        current_timestamp - interval '10 minutes',
        'failed',
        'smtp timeout',
        'event-welcome',
        :'notificationFailedID',
        current_timestamp - interval '10 minutes',
        :'userID'
    ),
    (
        1,
        current_timestamp - interval '10 minutes',
        'processed',
        null,
        'event-welcome',
        :'notificationProcessedID',
        current_timestamp - interval '10 minutes',
        :'userID'
    ),
    (
        2,
        current_timestamp - interval '20 minutes',
        'delivery-unknown',
        'delivery outcome unknown after processing timeout',
        'event-welcome',
        :'notificationUnknownID',
        current_timestamp - interval '5 minutes',
        :'userID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject missing notification ids
select throws_ok(
    $$select manual_requeue_notifications('{}'::uuid[], 'smtp recovered')$$,
    'P0001',
    'notification ids are required',
    'Should reject missing notification ids'
);

-- Should reject blank requeue reasons
select throws_ok(
    format(
        $$select manual_requeue_notifications(array[%L]::uuid[], ' ')$$,
        :'notificationFailedID'
    ),
    'P0001',
    'requeue reason is required',
    'Should reject blank requeue reasons'
);

-- Should requeue selected terminal notifications
select is(
    manual_requeue_notifications(
        array[
            :'notificationFailedID',
            :'notificationUnknownID',
            :'notificationProcessedID'
        ]::uuid[],
        'smtp recovered'
    ),
    2,
    'Should requeue selected terminal notifications'
);

-- Should reset terminal notifications for immediate delivery
select results_eq(
    format(
        $$
        select
            notification_id,
            delivery_attempts,
            delivery_claimed_at,
            delivery_status,
            error,
            next_delivery_attempt_at,
            processed_at
        from notification
        where notification_id in (%L::uuid, %L::uuid)
        order by notification_id
        $$,
        :'notificationFailedID',
        :'notificationUnknownID'
    ),
    format(
        $$
        values
            (%L::uuid, 0, null::timestamptz, 'pending'::text, 'smtp recovered'::text,
                null::timestamptz, null::timestamptz),
            (%L::uuid, 0, null::timestamptz, 'pending'::text, 'smtp recovered'::text,
                null::timestamptz, null::timestamptz)
        $$,
        :'notificationFailedID',
        :'notificationUnknownID'
    ),
    'Should reset terminal notifications for immediate delivery'
);

-- Should leave non-terminal notifications unchanged
select results_eq(
    format(
        $$
        select
            delivery_attempts,
            delivery_status,
            processed_at is not null
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationProcessedID'
    ),
    $$ values (1, 'processed'::text, true) $$,
    'Should leave non-terminal notifications unchanged'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
