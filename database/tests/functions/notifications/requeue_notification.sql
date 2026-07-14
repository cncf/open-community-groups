-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationCappedDelayID '8a070000-0000-0000-0000-000000000005'
\set notificationMaxAttemptsID '8a070000-0000-0000-0000-000000000001'
\set notificationProcessedID '8a070000-0000-0000-0000-000000000002'
\set notificationRetryID '8a070000-0000-0000-0000-000000000003'
\set notificationStaleClaimID '8a070000-0000-0000-0000-000000000006'
\set userID '8a070000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User who owns the retry notifications
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'user@example.com', true, 'user');

-- Processing and processed notifications used by the retry scenarios
insert into notification (
    notification_id,
    delivery_attempts,
    delivery_status,
    kind,
    user_id,

    delivery_claimed_at,
    processed_at
) values
    (:'notificationCappedDelayID', 6, 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:05+00', null),
    (:'notificationMaxAttemptsID', 10, 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:01+00', null),
    (:'notificationProcessedID', 1, 'processed', 'event-welcome', :'userID',
        '2025-01-01 00:00:02+00', current_timestamp),
    (:'notificationRetryID', 2, 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:03+00', null),
    (:'notificationStaleClaimID', 2, 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:06+00', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject blank errors
select throws_ok(
    format(
        $$select requeue_notification(
            %L::uuid, ' ', 60, 1800, 10, '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationRetryID'
    ),
    'P0001',
    'delivery error is required',
    'Should reject blank errors'
);

-- Should reject non-positive base retry delays
select throws_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 0, 1800, 10,
            '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationRetryID'
    ),
    'P0001',
    'base retry delay must be positive',
    'Should reject non-positive base retry delays'
);

-- Should reject null base retry delays
select throws_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', null, 1800, 10,
            '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationRetryID'
    ),
    'P0001',
    'base retry delay must be positive',
    'Should reject null base retry delays'
);

-- Should reject non-positive maximum retry delays
select throws_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 0, 10,
            '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationRetryID'
    ),
    'P0001',
    'maximum retry delay must be positive',
    'Should reject non-positive maximum retry delays'
);

-- Should reject null maximum retry delays
select throws_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, null, 10,
            '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationRetryID'
    ),
    'P0001',
    'maximum retry delay must be positive',
    'Should reject null maximum retry delays'
);

-- Should reject maximum retry delays less than the base delay
select throws_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 30, 10,
            '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationRetryID'
    ),
    'P0001',
    'maximum retry delay cannot be less than base retry delay',
    'Should reject maximum retry delays less than the base delay'
);

-- Should reject non-positive maximum delivery attempts
select throws_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 1800, 0,
            '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationRetryID'
    ),
    'P0001',
    'maximum delivery attempts must be positive',
    'Should reject non-positive maximum delivery attempts'
);

-- Should reject null maximum delivery attempts
select throws_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 1800, null,
            '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationRetryID'
    ),
    'P0001',
    'maximum delivery attempts must be positive',
    'Should reject null maximum delivery attempts'
);

-- Should requeue retryable failures below the durable attempt limit
select lives_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 1800, 10,
            '2025-01-01 00:00:03+00'::timestamptz
        )$$,
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
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 1800, 10,
            '2025-01-01 00:00:05+00'::timestamptz
        )$$,
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
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 1800, 10,
            '2025-01-01 00:00:01+00'::timestamptz
        )$$,
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
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 1800, 10,
            '2025-01-01 00:00:02+00'::timestamptz
        )$$,
        :'notificationProcessedID'
    ),
    'P0001',
    'notification delivery claim not found or no longer active',
    'Should reject notifications that are no longer being processed'
);

-- Should stop a stale worker from requeueing a newer delivery claim
select throws_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 1800, 10,
            '2025-01-01 00:00:04+00'::timestamptz
        )$$,
        :'notificationStaleClaimID'
    ),
    'P0001',
    'notification delivery claim not found or no longer active',
    'Should stop a stale worker from requeueing a newer delivery claim'
);

-- Should preserve the newer claim after a stale requeue attempt
select results_eq(
    format(
        $$
        select
            delivery_claimed_at,
            delivery_status,
            error,
            next_delivery_attempt_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationStaleClaimID'
    ),
    $$
        values (
            '2025-01-01 00:00:06+00'::timestamptz,
            'processing'::text,
            null::text,
            null::timestamptz
        )
    $$,
    'Should preserve the newer claim after a stale requeue attempt'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
