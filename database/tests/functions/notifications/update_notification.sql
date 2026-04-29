-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationID1 '00000000-0000-0000-0000-000000000101'
\set notificationID2 '00000000-0000-0000-0000-000000000102'
\set userID '00000000-0000-0000-0000-000000000201'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (auth_hash, email, email_verified, user_id, username)
values ('hash', 'user@example.com', true, :'userID', 'user');

-- Notifications
insert into notification (delivery_status, kind, notification_id, user_id) values
    ('processing', 'group-welcome', :'notificationID1', :'userID'),
    ('processing', 'event-welcome', :'notificationID2', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mark a notification as processed with an error
select lives_ok(
    $$select update_notification(
        '00000000-0000-0000-0000-000000000101'::uuid,
        'smtp timeout'
    )$$,
    'Should mark a notification as processed with an error'
);

-- Should persist processed fields and error
select results_eq(
    $$
        select
            delivery_status,
            error,
            processed_at is not null
        from notification
        where notification_id = '00000000-0000-0000-0000-000000000101'::uuid
    $$,
    $$ values ('failed'::text, 'smtp timeout'::text, true) $$,
    'Should persist processed fields and error'
);

-- Should mark a notification as processed without an error
select lives_ok(
    $$select update_notification(
        '00000000-0000-0000-0000-000000000102'::uuid,
        null::text
    )$$,
    'Should mark a notification as processed without an error'
);

-- Should persist processed fields and clear error
select results_eq(
    $$
        select
            delivery_status,
            error,
            processed_at is not null
        from notification
        where notification_id = '00000000-0000-0000-0000-000000000102'::uuid
    $$,
    $$ values ('processed'::text, null::text, true) $$,
    'Should persist processed fields and clear error'
);

-- Should reject updating a notification that is not being processed
select throws_ok(
    $$select update_notification(
        '00000000-0000-0000-0000-000000000102'::uuid,
        null::text
    )$$,
    'P0001',
    'claimed notification not found or already finalized',
    'Should reject updating a notification that is not being processed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
