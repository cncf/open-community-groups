-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationCappedDelayID '8a070000-0000-0000-0000-000000000005'
\set notificationMaxAttemptsID '8a070000-0000-0000-0000-000000000001'
\set notificationProcessedID '8a070000-0000-0000-0000-000000000002'
\set notificationRetryID '8a070000-0000-0000-0000-000000000003'
\set userID '8a070000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'user@example.com', true, 'user');

-- Notifications
insert into notification (
    delivery_attempts,
    delivery_status,
    kind,
    notification_id,
    processed_at,
    user_id
) values
    (6, 'processing', 'event-welcome', :'notificationCappedDelayID', null, :'userID'),
    (10, 'processing', 'event-welcome', :'notificationMaxAttemptsID', null, :'userID'),
    (1, 'processed', 'event-welcome', :'notificationProcessedID', current_timestamp, :'userID'),
    (2, 'processing', 'event-welcome', :'notificationRetryID', null, :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject blank errors
select throws_ok(
    format(
        $$select requeue_notification(%L::uuid, ' ', 60, 1800, 10)$$,
        :'notificationRetryID'
    ),
    'P0001',
    'delivery error is required',
    'Should reject blank errors'
);

-- Should reject non-positive base retry delays
select throws_ok(
    format(
        $$select requeue_notification(%L::uuid, 'smtp timeout', 0, 1800, 10)$$,
        :'notificationRetryID'
    ),
    'P0001',
    'base retry delay must be positive',
    'Should reject non-positive base retry delays'
);

-- Should reject non-positive maximum retry delays
select throws_ok(
    format(
        $$select requeue_notification(%L::uuid, 'smtp timeout', 60, 0, 10)$$,
        :'notificationRetryID'
    ),
    'P0001',
    'maximum retry delay must be positive',
    'Should reject non-positive maximum retry delays'
);

-- Should reject maximum retry delays less than the base delay
select throws_ok(
    format(
        $$select requeue_notification(%L::uuid, 'smtp timeout', 60, 30, 10)$$,
        :'notificationRetryID'
    ),
    'P0001',
    'maximum retry delay cannot be less than base retry delay',
    'Should reject maximum retry delays less than the base delay'
);

-- Should reject non-positive maximum delivery attempts
select throws_ok(
    format(
        $$select requeue_notification(%L::uuid, 'smtp timeout', 60, 1800, 0)$$,
        :'notificationRetryID'
    ),
    'P0001',
    'maximum delivery attempts must be positive',
    'Should reject non-positive maximum delivery attempts'
);

-- Should requeue retryable failures below the durable attempt limit
select lives_ok(
    format(
        $$select requeue_notification(%L::uuid, 'smtp timeout', 60, 1800, 10)$$,
        :'notificationRetryID'
    ),
    'Should requeue retryable failures below the durable attempt limit'
);

-- Should persist retry metadata for requeued notifications
select results_eq(
    format(
        $$
        select
            delivery_status,
            error,
            next_delivery_attempt_at,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationRetryID'
    ),
    $$
        values (
            'pending'::text,
            'smtp timeout'::text,
            current_timestamp + interval '2 minutes',
            null::timestamptz
        )
    $$,
    'Should persist retry metadata for requeued notifications'
);

-- Should requeue with the capped retry delay
select lives_ok(
    format(
        $$select requeue_notification(%L::uuid, 'smtp timeout', 60, 1800, 10)$$,
        :'notificationCappedDelayID'
    ),
    'Should requeue with the capped retry delay'
);

-- Should cap retry delay at the maximum retry delay
select results_eq(
    format(
        $$
        select
            delivery_status,
            error,
            next_delivery_attempt_at,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationCappedDelayID'
    ),
    $$
        values (
            'pending'::text,
            'smtp timeout'::text,
            current_timestamp + interval '30 minutes',
            null::timestamptz
        )
    $$,
    'Should cap retry delay at the maximum retry delay'
);

-- Should finalize retryable failures at the durable attempt limit
select lives_ok(
    format(
        $$select requeue_notification(%L::uuid, 'smtp timeout', 60, 1800, 10)$$,
        :'notificationMaxAttemptsID'
    ),
    'Should finalize retryable failures at the durable attempt limit'
);

-- Should persist terminal failure metadata at the durable attempt limit
select results_eq(
    format(
        $$
        select
            delivery_status,
            error,
            next_delivery_attempt_at,
            processed_at is not null
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationMaxAttemptsID'
    ),
    $$ values ('failed'::text, 'smtp timeout'::text, null::timestamptz, true) $$,
    'Should persist terminal failure metadata at the durable attempt limit'
);

-- Should reject notifications that are no longer being processed
select throws_ok(
    format(
        $$select requeue_notification(%L::uuid, 'smtp timeout', 60, 1800, 10)$$,
        :'notificationProcessedID'
    ),
    'P0001',
    'claimed notification not found or already finalized',
    'Should reject notifications that are no longer being processed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
