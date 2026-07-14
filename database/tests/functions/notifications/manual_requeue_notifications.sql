-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

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

-- User who owns the manual-requeue notifications
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'user@example.com', true, 'user');

-- Terminal and processed notifications used by the manual-requeue scenarios
insert into notification (
    created_at,
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
        '2025-01-01 00:00:01',
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
        '2025-01-01 00:00:03',
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
        '2025-01-01 00:00:02',
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

-- Should preserve manual requeue history for every changed notification
select results_eq(
    $$
        select
            action,
            resource_id,
            resource_type,
            actor_user_id,
            details
        from audit_log
        where action = 'notification_manually_requeued'
        order by resource_id
    $$,
    format(
        $$
        values
            (
                'notification_manually_requeued'::text,
                %L::uuid,
                'notification'::text,
                null::uuid,
                jsonb_build_object(
                    'database_user', current_user,
                    'previous_delivery_status', 'failed',
                    'previous_error', 'smtp timeout',
                    'reason', 'smtp recovered'
                )
            ),
            (
                'notification_manually_requeued'::text,
                %L::uuid,
                'notification'::text,
                null::uuid,
                jsonb_build_object(
                    'database_user', current_user,
                    'previous_delivery_status', 'delivery-unknown',
                    'previous_error', 'delivery outcome unknown after processing timeout',
                    'reason', 'smtp recovered'
                )
            )
        $$,
        :'notificationFailedID',
        :'notificationUnknownID'
    ),
    'Should preserve manual requeue history for every changed notification'
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

-- Should claim the oldest manually requeued notification
select is(
    (select notification_id from claim_pending_notification()),
    :'notificationFailedID'::uuid,
    'Should claim the oldest manually requeued notification'
);

-- Should retain the audit reason after a new delivery claim clears the transient error
select results_eq(
    format(
        $$
        select
            n.error,
            al.details->>'reason'
        from notification n
        join audit_log al on al.resource_id = n.notification_id
        where n.notification_id = %L::uuid
        and al.action = 'notification_manually_requeued'
        $$,
        :'notificationFailedID'
    ),
    $$ values (null::text, 'smtp recovered'::text) $$,
    'Should retain the audit reason after a new delivery claim clears the transient error'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
