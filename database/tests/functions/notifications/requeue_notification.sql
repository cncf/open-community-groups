-- Tests requeueing claimed notifications after retryable delivery failures.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(22);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationCappedDelayID '8a000000-0000-0000-0000-000000000005'
\set notificationMaxAttemptsID '8a000000-0000-0000-0000-000000000001'
\set notificationPasswordResetExhaustedID '8a000000-0000-0000-0000-000000000007'
\set notificationPasswordResetInactiveID '8a000000-0000-0000-0000-000000000008'
\set notificationProcessedID '8a000000-0000-0000-0000-000000000002'
\set notificationRetryID '8a000000-0000-0000-0000-000000000003'
\set notificationStaleClaimID '8a000000-0000-0000-0000-000000000006'
\set tplPasswordResetExhaustedID '8a000000-0000-0000-0000-000000000009'
\set tplPasswordResetInactiveID '8a000000-0000-0000-0000-000000000010'
\set userID '8a000000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Template data for an exhausted password-reset notification
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'tplPasswordResetExhaustedID',
    '{"link":"https://example.test/reset-password/8a00-exhausted"}'::jsonb,
    encode(digest('8a00-password-reset-exhausted', 'sha256'), 'hex')
);

-- Template data for a password-reset notification whose token was already revoked
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'tplPasswordResetInactiveID',
    '{"link":"https://example.test/reset-password/8a00-inactive"}'::jsonb,
    encode(digest('8a00-password-reset-inactive', 'sha256'), 'hex')
);

-- User who owns the retry notifications
select fx_user(:'userID', jsonb_build_object('username', 'user-requeue-notification'));

-- Processing and processed notifications used by the retry scenarios
insert into notification (
    notification_id,
    delivery_attempts,
    delivery_status,
    kind,
    user_id,

    delivery_claimed_at,
    notification_template_data_id,
    processed_at
) values
    (:'notificationCappedDelayID', 6, 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:05+00', null, null),
    (:'notificationMaxAttemptsID', 10, 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:01+00', null, null),
    (:'notificationPasswordResetExhaustedID', 10, 'processing', 'password-reset', :'userID',
        '2025-01-01 00:00:07+00', :'tplPasswordResetExhaustedID', null),
    (:'notificationPasswordResetInactiveID', 1, 'processing', 'password-reset', :'userID',
        '2025-01-01 00:00:08+00', :'tplPasswordResetInactiveID', null),
    (:'notificationProcessedID', 1, 'processed', 'event-welcome', :'userID',
        '2025-01-01 00:00:02+00', null, current_timestamp),
    (:'notificationRetryID', 2, 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:03+00', null, null),
    (:'notificationStaleClaimID', 2, 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:06+00', null, null);

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
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationMaxAttemptsID'
    ),
    $$ values ('failed'::text, 'smtp timeout'::text, null::timestamptz, current_timestamp) $$,
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

-- Should scrub template data when a password-reset notification exhausts retry attempts
select lives_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 1800, 10,
            '2025-01-01 00:00:07+00'::timestamptz
        )$$,
        :'notificationPasswordResetExhaustedID'
    ),
    'Should finalize an exhausted password-reset notification'
);
select results_eq(
    format(
        $$
            select delivery_status, notification_template_data_id is null
            from notification
            where notification_id = %L::uuid
        $$,
        :'notificationPasswordResetExhaustedID'
    ),
    $$values ('failed'::text, true)$$,
    'Should detach template data from an exhausted password-reset notification'
);
select is(
    (
        select count(*)::int
        from notification_template_data
        where notification_template_data_id = :'tplPasswordResetExhaustedID'::uuid
    ),
    0,
    'Should delete template data of an exhausted password-reset notification'
);

-- Should fail and scrub a password-reset notification whose token is no longer active
select lives_ok(
    format(
        $$select requeue_notification(
            %L::uuid, 'smtp timeout', 60, 1800, 10,
            '2025-01-01 00:00:08+00'::timestamptz
        )$$,
        :'notificationPasswordResetInactiveID'
    ),
    'Should fail a password-reset notification whose token is no longer active'
);
select results_eq(
    format(
        $$
            select delivery_status, error, notification_template_data_id is null
            from notification
            where notification_id = %L::uuid
        $$,
        :'notificationPasswordResetInactiveID'
    ),
    $$values ('failed'::text, 'password reset token no longer active'::text, true)$$,
    'Should finalize and detach a password-reset notification with no active token'
);
select is(
    (
        select count(*)::int
        from notification_template_data
        where notification_template_data_id = :'tplPasswordResetInactiveID'::uuid
    ),
    0,
    'Should delete template data of an inactive-token password-reset notification'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
