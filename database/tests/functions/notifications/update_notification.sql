-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

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
insert into notification (kind, notification_id, user_id) values
    ('group-welcome', :'notificationID1', :'userID'),
    ('event-welcome', :'notificationID2', :'userID');

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
            error,
            processed,
            processed_at is not null
        from notification
        where notification_id = '00000000-0000-0000-0000-000000000101'::uuid
    $$,
    $$ values ('smtp timeout'::text, true, true) $$,
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
            error,
            processed,
            processed_at is not null
        from notification
        where notification_id = '00000000-0000-0000-0000-000000000102'::uuid
    $$,
    $$ values (null::text, true, true) $$,
    'Should persist processed fields and clear error'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
