-- Tests finalizing claimed notifications after delivery attempts.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationBlankErrorID '8a060000-0000-0000-0000-000000000006'
\set notificationID1 '8a060000-0000-0000-0000-000000000001'
\set notificationID2 '8a060000-0000-0000-0000-000000000002'
\set notificationProcessedID '8a060000-0000-0000-0000-000000000005'
\set notificationStaleClaimID '8a060000-0000-0000-0000-000000000004'
\set userID '8a060000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
select fx_user(:'userID', jsonb_build_object('username', 'user-update-notification'));

-- Processing and processed notifications used by the finalization and validation scenarios
insert into notification (
    notification_id,
    delivery_status,
    kind,
    user_id,

    delivery_claimed_at,
    processed_at
) values
    (:'notificationBlankErrorID', 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:06+00', null),
    (:'notificationID1', 'processing', 'group-welcome', :'userID', '2025-01-01 00:00:01+00',
        null),
    (:'notificationID2', 'processing', 'event-welcome', :'userID', '2025-01-01 00:00:02+00',
        null),
    (:'notificationProcessedID', 'processed', 'event-welcome', :'userID',
        '2025-01-01 00:00:05+00', '2025-01-01 00:00:06+00'),
    (:'notificationStaleClaimID', 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:04+00', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mark a notification as processed with an error
select lives_ok(
    format(
        $$select update_notification(
        %L::uuid,
        'smtp timeout',
        '2025-01-01 00:00:01+00'::timestamptz
        )$$,
        :'notificationID1'
    ),
    'Should mark a notification as processed with an error'
);

-- Should persist processed fields and error
select results_eq(
    format(
        $$
        select
            delivery_status,
            error,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationID1'
    ),
    $$ values ('failed'::text, 'smtp timeout'::text, current_timestamp) $$,
    'Should persist processed fields and error'
);

-- Should mark a notification as processed without an error
select lives_ok(
    format(
        $$select update_notification(
        %L::uuid,
        null::text,
        '2025-01-01 00:00:02+00'::timestamptz
        )$$,
        :'notificationID2'
    ),
    'Should mark a notification as processed without an error'
);

-- Should persist processed fields and clear error
select results_eq(
    format(
        $$
        select
            delivery_status,
            error,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationID2'
    ),
    $$ values ('processed'::text, null::text, current_timestamp) $$,
    'Should persist processed fields and clear error'
);

-- Should reject blank delivery errors
select throws_ok(
    format(
        $$select update_notification(
        %L::uuid,
        ' ',
        '2025-01-01 00:00:06+00'::timestamptz
        )$$,
        :'notificationBlankErrorID'
    ),
    'P0001',
    'delivery error is required',
    'Should reject blank delivery errors'
);

-- Should reject updating a notification that is not being processed
select throws_ok(
    format(
        $$select update_notification(
        %L::uuid,
        null::text,
        '2025-01-01 00:00:05+00'::timestamptz
        )$$,
        :'notificationProcessedID'
    ),
    'P0001',
    'notification delivery claim not found or no longer active',
    'Should reject updating a notification that is not being processed'
);

-- Should stop a stale worker from finalizing a newer delivery claim
select throws_ok(
    format(
        $$select update_notification(
        %L::uuid,
        null::text,
        '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationStaleClaimID'
    ),
    'P0001',
    'notification delivery claim not found or no longer active',
    'Should stop a stale worker from finalizing a newer delivery claim'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
