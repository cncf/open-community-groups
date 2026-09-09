-- Tests release_notification returns interrupted claims to the queue.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationFinalClaimID '8a0a0000-0000-0000-0000-000000000001'
\set notificationProcessedID '8a0a0000-0000-0000-0000-000000000002'
\set notificationReleaseID '8a0a0000-0000-0000-0000-000000000003'
\set notificationStaleClaimID '8a0a0000-0000-0000-0000-000000000004'
\set userID '8a0a0000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Registered user with a verified email so released notifications stay claimable
select fx_user(:'userID', jsonb_build_object(
    'email_verified', true,
    'registration_status', 'registered',
    'username', 'user-release-notification'
));

-- Processing and processed notifications used by the release scenarios
insert into notification (
    created_at,
    delivery_attempts,
    delivery_status,
    kind,
    notification_id,
    user_id,

    delivery_claimed_at,
    error,
    processed_at
) values
    ('2025-01-01 00:00:00+00', 10, 'processing', 'event-welcome', :'notificationFinalClaimID',
        :'userID', '2025-01-01 00:00:01+00', null, null),
    ('2025-01-02 00:00:00+00', 1, 'processed', 'event-welcome', :'notificationProcessedID',
        :'userID', '2025-01-01 00:00:02+00', null, current_timestamp),
    ('2025-01-03 00:00:00+00', 2, 'processing', 'event-welcome', :'notificationReleaseID',
        :'userID', '2025-01-01 00:00:03+00', 'previous smtp timeout', null),
    ('2025-01-04 00:00:00+00', 2, 'processing', 'event-welcome', :'notificationStaleClaimID',
        :'userID', '2025-01-01 00:00:06+00', null, null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release an active claim back to the queue
select lives_ok(
    format(
        $$select release_notification(%L::uuid, '2025-01-01 00:00:03+00'::timestamptz)$$,
        :'notificationReleaseID'
    ),
    'Should release an active claim back to the queue'
);

-- Should make the notification pending now without spending delivery budget
select results_eq(
    format(
        $$
        select
            delivery_attempts,
            delivery_status,
            error,
            next_delivery_attempt_at,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationReleaseID'
    ),
    $$
        values (
            2,
            'pending'::text,
            'previous smtp timeout'::text,
            current_timestamp,
            null::timestamptz
        )
    $$,
    'Should make the notification pending now without spending delivery budget'
);

-- Should release a claim that already reached the delivery attempt limit
select lives_ok(
    format(
        $$select release_notification(%L::uuid, '2025-01-01 00:00:01+00'::timestamptz)$$,
        :'notificationFinalClaimID'
    ),
    'Should release a claim that already reached the delivery attempt limit'
);

-- Should leave the final-claim notification pending instead of failed
select results_eq(
    format(
        $$
        select delivery_attempts, delivery_status, next_delivery_attempt_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationFinalClaimID'
    ),
    $$ values (10, 'pending'::text, current_timestamp) $$,
    'Should leave the final-claim notification pending instead of failed'
);

-- Should keep the released final-claim notification claimable
select is(
    (select notification_id from claim_pending_notification(1, 60)),
    :'notificationFinalClaimID'::uuid,
    'Should keep the released final-claim notification claimable'
);

-- Should reject notifications that are no longer being processed
select throws_ok(
    format(
        $$select release_notification(%L::uuid, '2025-01-01 00:00:02+00'::timestamptz)$$,
        :'notificationProcessedID'
    ),
    'P0001',
    'notification delivery claim not found or no longer active',
    'Should reject notifications that are no longer being processed'
);

-- Should stop a stale worker from releasing a newer delivery claim
select throws_ok(
    format(
        $$select release_notification(%L::uuid, '2025-01-01 00:00:04+00'::timestamptz)$$,
        :'notificationStaleClaimID'
    ),
    'P0001',
    'notification delivery claim not found or no longer active',
    'Should stop a stale worker from releasing a newer delivery claim'
);

-- Should preserve the newer claim after a stale release attempt
select results_eq(
    format(
        $$
        select delivery_claimed_at, delivery_status, next_delivery_attempt_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationStaleClaimID'
    ),
    $$
        values (
            '2025-01-01 00:00:06+00'::timestamptz,
            'processing'::text,
            null::timestamptz
        )
    $$,
    'Should preserve the newer claim after a stale release attempt'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
