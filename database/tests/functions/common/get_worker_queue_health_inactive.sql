-- Tests worker queue backlog signals when no notification is pending or in flight.
-- Split from get_worker_queue_health.sql because the base file seeds pending
-- and processing notifications, which contradict a queue without active work.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set failedNotificationID 'b0060000-0000-0000-0000-000000000001'
\set processedNotificationID 'b0060000-0000-0000-0000-000000000002'
\set unknownNotificationID 'b0060000-0000-0000-0000-000000000003'
\set userID 'b0060000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User receiving the notifications
select fx_user(:'userID');

-- Notifications that left the queue: one failed, one processed, one with an unknown delivery
insert into notification (
    notification_id, created_at, delivery_attempts, delivery_claimed_at, delivery_status,
    kind, user_id
) values
    (:'failedNotificationID', current_timestamp - interval '1 hour', 3, null, 'failed',
        'event-canceled', :'userID'),
    (:'processedNotificationID', current_timestamp - interval '2 hours', 1, null,
        'processed', 'event-canceled', :'userID'),
    (:'unknownNotificationID', current_timestamp - interval '3 hours', 1, null,
        'delivery-unknown', 'event-canceled', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count no notifications and report no age when none is pending or processing
select is(
    (get_worker_queue_health()->'notifications')::jsonb,
    '{"pending": 0, "processing": 0, "oldest_pending_age_secs": null}'::jsonb,
    'Should count no notifications and report no age when none is pending or processing'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
