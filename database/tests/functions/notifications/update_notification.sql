-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationID1 '8a060000-0000-0000-0000-000000000001'
\set notificationID2 '8a060000-0000-0000-0000-000000000002'
\set userID '8a060000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'user@example.com', true, 'user');

-- Notifications
insert into notification (delivery_status, kind, notification_id, user_id) values
    ('processing', 'group-welcome', :'notificationID1', :'userID'),
    ('processing', 'event-welcome', :'notificationID2', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mark a notification as processed with an error
select lives_ok(
    format(
        $$select update_notification(
        %L::uuid,
        'smtp timeout'
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
        null::text
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
        null::text
        )$$,
        :'notificationID2'
    ),
    'P0001',
    'claimed notification not found or already finalized',
    'Should reject updating a notification that is not being processed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
