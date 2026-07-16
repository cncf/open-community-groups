-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationProcessedID '8a090000-0000-0000-0000-000000000001'
\set notificationProcessingID '8a090000-0000-0000-0000-000000000002'
\set notificationStaleClaimID '8a090000-0000-0000-0000-000000000004'
\set userID '8a090000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User who owns the delivery notifications
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'user@example.com', true, 'user');

-- Processed notification rejected by the invalid-state scenario
insert into notification (
    notification_id,
    delivery_attempts,
    delivery_status,
    kind,
    user_id,

    processed_at
) values (
    :'notificationProcessedID',
    1,
    'processed',
    'event-welcome',
    :'userID',

    '2025-01-01 00:00:01+00'
);

-- Processing notification used by the unknown-outcome scenarios
insert into notification (
    notification_id,
    delivery_attempts,
    delivery_status,
    kind,
    user_id,

    delivery_claimed_at
) values (
    :'notificationProcessingID',
    2,
    'processing',
    'event-welcome',
    :'userID',

    '2025-01-01 00:00:02+00'
);

-- Processing notification with a newer claim than the stale worker holds
insert into notification (
    notification_id,
    delivery_attempts,
    delivery_status,
    kind,
    user_id,

    delivery_claimed_at
) values (
    :'notificationStaleClaimID',
    3,
    'processing',
    'event-welcome',
    :'userID',

    '2025-01-01 00:00:04+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mark a claimed notification with an unknown delivery outcome
select lives_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid,
            'network error: connection reset by peer',
            '2025-01-01 00:00:02+00'::timestamptz
        )$$,
        :'notificationProcessingID'
    ),
    'Should mark a claimed notification with an unknown delivery outcome'
);

-- Should persist the unknown outcome without changing claim metadata
select results_eq(
    format(
        $$
        select
            delivery_attempts,
            delivery_claimed_at is not null,
            delivery_status,
            error,
            next_delivery_attempt_at,
            processed_at is not null
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationProcessingID'
    ),
    $$
        values (
            2,
            true,
            'delivery-unknown'::text,
            'network error: connection reset by peer'::text,
            null::timestamptz,
            true
        )
    $$,
    'Should persist the unknown outcome without changing claim metadata'
);

-- Should reject blank delivery errors
select throws_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid, ' ', '2025-01-01 00:00:02+00'::timestamptz
        )$$,
        :'notificationProcessingID'
    ),
    'P0001',
    'delivery error is required',
    'Should reject blank delivery errors'
);

-- Should reject notifications that are no longer being processed
select throws_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid, 'network error', '2025-01-01 00:00:01+00'::timestamptz
        )$$,
        :'notificationProcessedID'
    ),
    'P0001',
    'notification delivery claim not found or no longer active',
    'Should reject notifications that are no longer being processed'
);

-- Should reject null delivery errors
select throws_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid, null::text, '2025-01-01 00:00:02+00'::timestamptz
        )$$,
        :'notificationProcessingID'
    ),
    'P0001',
    'delivery error is required',
    'Should reject null delivery errors'
);

-- Should stop a stale worker from marking a newer delivery claim unknown
select throws_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid,
            'network error',
            '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationStaleClaimID'
    ),
    'P0001',
    'notification delivery claim not found or no longer active',
    'Should stop a stale worker from marking a newer delivery claim unknown'
);

-- Should preserve the newer claim after a stale unknown-outcome attempt
select results_eq(
    format(
        $$
        select
            delivery_claimed_at,
            delivery_status,
            error,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationStaleClaimID'
    ),
    $$
        values (
            '2025-01-01 00:00:04+00'::timestamptz,
            'processing'::text,
            null::text,
            null::timestamptz
        )
    $$,
    'Should preserve the newer claim after a stale unknown-outcome attempt'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
