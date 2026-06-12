-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationFreshProcessingID '8a040000-0000-0000-0000-000000000001'
\set notificationPendingID '8a040000-0000-0000-0000-000000000002'
\set notificationProcessedID '8a040000-0000-0000-0000-000000000003'
\set notificationStaleProcessingID '8a040000-0000-0000-0000-000000000004'
\set userID '8a040000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'user@example.com', true, 'user');

-- Notifications
insert into notification (
    delivery_claimed_at,
    delivery_status,
    kind,
    notification_id,
    processed_at,
    user_id
) values
    (
        current_timestamp - interval '5 minutes',
        'processing',
        'group-welcome',
        :'notificationFreshProcessingID',
        null,
        :'userID'
    ),
    (
        current_timestamp - interval '30 minutes',
        'pending',
        'group-welcome',
        :'notificationPendingID',
        null,
        :'userID'
    ),
    (
        current_timestamp - interval '30 minutes',
        'processed',
        'group-welcome',
        :'notificationProcessedID',
        current_timestamp - interval '30 minutes',
        :'userID'
    ),
    (
        current_timestamp - interval '30 minutes',
        'processing',
        'group-welcome',
        :'notificationStaleProcessingID',
        null,
        :'userID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject non-positive timeouts
select throws_ok(
    $$select mark_stale_processing_notifications_unknown(0)$$,
    'P0001',
    'processing timeout must be positive',
    'Should reject non-positive timeouts'
);

-- Should mark only stale processing notifications
select is(
    mark_stale_processing_notifications_unknown(900),
    1,
    'Marks only stale processing notifications'
);

-- Should persist delivery-unknown state for stale claims
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
        :'notificationStaleProcessingID'
    ),
    $$
        values (
            'delivery-unknown'::text,
            'delivery outcome unknown after processing timeout'::text,
            true
        )
    $$,
    'Persists delivery-unknown state for stale claims'
);

-- Should leave fresh processing notifications active
select results_eq(
    format(
        $$
        select
            delivery_status,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationFreshProcessingID'
    ),
    $$ values ('processing'::text, null::timestamptz) $$,
    'Leaves fresh processing notifications active'
);

-- Should leave other delivery statuses unchanged
select results_eq(
    format(
        $$
        select
            notification_id,
            delivery_status
        from notification
        where notification_id in (
            %L::uuid,
            %L::uuid
        )
        order by notification_id
        $$,
        :'notificationPendingID',
        :'notificationProcessedID'
    ),
    format(
        $$
        values
            (%L::uuid, 'pending'::text),
            (%L::uuid, 'processed'::text)
        $$,
        :'notificationPendingID',
        :'notificationProcessedID'
    ),
    'Leaves other delivery statuses unchanged'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
