-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationID1 '8a060000-0000-0000-0000-000000000001'
\set notificationID2 '8a060000-0000-0000-0000-000000000002'
\set notificationStaleClaimID '8a060000-0000-0000-0000-000000000004'
\set userID '8a060000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'user@example.com', true, 'user');

-- Processing notifications used by current and stale claim scenarios
insert into notification (
    notification_id,
    delivery_status,
    kind,
    user_id,

    delivery_claimed_at
) values
    (:'notificationID1', 'processing', 'group-welcome', :'userID', '2025-01-01 00:00:01+00'),
    (:'notificationID2', 'processing', 'event-welcome', :'userID', '2025-01-01 00:00:02+00'),
    (:'notificationStaleClaimID', 'processing', 'event-welcome', :'userID',
        '2025-01-01 00:00:04+00');

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
            processed_at is not null
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationID1'
    ),
    $$ values ('failed'::text, 'smtp timeout'::text, true) $$,
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
            processed_at is not null
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationID2'
    ),
    $$ values ('processed'::text, null::text, true) $$,
    'Should persist processed fields and clear error'
);

-- Should reject updating a notification that is not being processed
select throws_ok(
    format(
        $$select update_notification(
        %L::uuid,
        null::text,
        '2025-01-01 00:00:02+00'::timestamptz
        )$$,
        :'notificationID2'
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

-- Should preserve the newer claim after a stale finalization attempt
select results_eq(
    format(
        $$
        select
            delivery_claimed_at,
            delivery_status,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationStaleClaimID'
    ),
    $$ values ('2025-01-01 00:00:04+00'::timestamptz, 'processing'::text, null::timestamptz) $$,
    'Should preserve the newer claim after a stale finalization attempt'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
