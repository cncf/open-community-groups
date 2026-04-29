-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationFreshProcessingID '00000000-0000-0000-0000-000000000101'
\set notificationPendingID '00000000-0000-0000-0000-000000000102'
\set notificationProcessedID '00000000-0000-0000-0000-000000000103'
\set notificationStaleProcessingID '00000000-0000-0000-0000-000000000104'
\set userID '00000000-0000-0000-0000-000000000201'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (auth_hash, email, email_verified, user_id, username)
values ('hash', 'user@example.com', true, :'userID', 'user');

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
    $$
        select
            delivery_status,
            error,
            processed_at is not null
        from notification
        where notification_id = '00000000-0000-0000-0000-000000000104'
    $$,
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
    $$
        select
            delivery_status,
            processed_at
        from notification
        where notification_id = '00000000-0000-0000-0000-000000000101'
    $$,
    $$ values ('processing'::text, null::timestamptz) $$,
    'Leaves fresh processing notifications active'
);

-- Should leave other delivery statuses unchanged
select results_eq(
    $$
        select
            notification_id,
            delivery_status
        from notification
        where notification_id in (
            '00000000-0000-0000-0000-000000000102',
            '00000000-0000-0000-0000-000000000103'
        )
        order by notification_id
    $$,
    $$
        values
            ('00000000-0000-0000-0000-000000000102'::uuid, 'pending'::text),
            ('00000000-0000-0000-0000-000000000103'::uuid, 'processed'::text)
    $$,
    'Leaves other delivery statuses unchanged'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
