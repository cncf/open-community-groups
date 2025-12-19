-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attachmentID1 '00000000-0000-0000-0000-000000000501'
\set attachmentID2 '00000000-0000-0000-0000-000000000502'
\set communityID '00000000-0000-0000-0000-000000000001'
\set notificationEmailVerificationID '00000000-0000-0000-0000-000000000101'
\set notificationEventPublishedID '00000000-0000-0000-0000-000000000102'
\set notificationGroupWelcomeID '00000000-0000-0000-0000-000000000103'
\set notificationProcessedID '00000000-0000-0000-0000-000000000104'
\set notificationUnverifiedEventPublishedID '00000000-0000-0000-0000-000000000105'
\set notificationUnverifiedGroupWelcomeID '00000000-0000-0000-0000-000000000106'
\set notificationWithAttachmentsID '00000000-0000-0000-0000-000000000107'
\set templateEmailVerificationID '00000000-0000-0000-0000-000000000301'
\set templateEventPublishedID '00000000-0000-0000-0000-000000000302'
\set templateGroupWelcomeID '00000000-0000-0000-0000-000000000303'
\set userUnverifiedID '00000000-0000-0000-0000-000000000201'
\set userVerifiedID '00000000-0000-0000-0000-000000000202'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'test.example.org',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Users
insert into "user" (user_id, community_id, email, email_verified, username, auth_hash) values
    (:'userVerifiedID', :'communityID', 'verified@example.com', true, 'verified', 'hash1'),
    (:'userUnverifiedID', :'communityID', 'unverified@example.com', false, 'unverified', 'hash2');

-- Notification templates
insert into notification_template_data (notification_template_data_id, data, hash) values
    (:'templateEmailVerificationID', '{"link": "https://example.com/verify"}'::jsonb, 'hash_email_verification'),
    (:'templateEventPublishedID', '{"event": "test"}'::jsonb, 'hash_event_published'),
    (:'templateGroupWelcomeID', '{"group": "test"}'::jsonb, 'hash_group_welcome');

-- Notifications for verified user (with explicit created_at for FIFO ordering)
insert into notification (notification_id, user_id, kind, notification_template_data_id, created_at) values
    (:'notificationEmailVerificationID', :'userVerifiedID', 'email-verification', :'templateEmailVerificationID', '2025-01-01 00:00:01'),
    (:'notificationEventPublishedID', :'userVerifiedID', 'event-published', :'templateEventPublishedID', '2025-01-01 00:00:02'),
    (:'notificationGroupWelcomeID', :'userVerifiedID', 'group-welcome', :'templateGroupWelcomeID', '2025-01-01 00:00:03');

-- Processed notification (should be skipped)
insert into notification (notification_id, user_id, kind, processed, processed_at, created_at) values
    (:'notificationProcessedID', :'userVerifiedID', 'group-welcome', true, current_timestamp, '2025-01-01 00:00:04');

-- Notifications for unverified user
insert into notification (notification_id, user_id, kind, created_at) values
    (:'notificationUnverifiedEventPublishedID', :'userUnverifiedID', 'event-published', '2025-01-01 00:00:05'),
    (:'notificationUnverifiedGroupWelcomeID', :'userUnverifiedID', 'group-welcome', '2025-01-01 00:00:06');

-- Notification with attachments
insert into notification (notification_id, user_id, kind, created_at) values
    (:'notificationWithAttachmentsID', :'userVerifiedID', 'event-welcome', '2025-01-01 00:00:07');
insert into attachment (attachment_id, content_type, data, file_name, hash) values
    (:'attachmentID1', 'text/calendar', 'BEGIN:VCALENDAR'::bytea, 'event.ics', 'hash1'),
    (:'attachmentID2', 'application/pdf', 'PDF'::bytea, 'ticket.pdf', 'hash2');
insert into notification_attachment (notification_id, attachment_id) values
    (:'notificationWithAttachmentsID', :'attachmentID1'),
    (:'notificationWithAttachmentsID', :'attachmentID2');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return NULL when no pending notifications exist
-- Mark all as processed to test empty queue
update notification set processed = true, processed_at = current_timestamp;
select is(
    (select notification_id from get_pending_notification()),
    null::uuid,
    'Returns NULL when no pending notifications exist'
);
-- Reset for remaining tests
update notification set processed = false, processed_at = null where notification_id != :'notificationProcessedID';

-- Should return oldest unprocessed notification first (FIFO order)
select is(
    (select notification_id from get_pending_notification()),
    :'notificationEmailVerificationID'::uuid,
    'Returns oldest unprocessed notification first (FIFO order)'
);

-- Should skip already-processed notifications
update notification set processed = true where notification_id = :'notificationEmailVerificationID';
select isnt(
    (select notification_id from get_pending_notification()),
    :'notificationEmailVerificationID'::uuid,
    'Skips already-processed notifications'
);
update notification set processed = false where notification_id = :'notificationEmailVerificationID';

-- Should return all expected fields
select is(
    (select row_to_json(r)::jsonb from get_pending_notification() r),
    jsonb_build_object(
        'attachment_ids', null,
        'email', 'verified@example.com',
        'kind', 'email-verification',
        'notification_id', :'notificationEmailVerificationID',
        'template_data', '{"link": "https://example.com/verify"}'::jsonb
    ),
    'Returns all expected fields'
);

-- Mark first notification as processed to test the next ones
update notification set processed = true where notification_id = :'notificationEmailVerificationID';

-- Should return notification for verified user
select is(
    (select notification_id from get_pending_notification()),
    :'notificationEventPublishedID'::uuid,
    'Notification for verified user is returned'
);

-- Should NOT return notification for unverified user
-- Mark all verified user notifications as processed, unverified should be skipped
update notification set processed = true where user_id = :'userVerifiedID';
select is(
    (select notification_id from get_pending_notification()),
    null::uuid,
    'Notification for unverified user is NOT returned'
);

-- Should return email verification notification for unverified user
insert into notification (notification_id, user_id, kind, notification_template_data_id, created_at) values
    ('00000000-0000-0000-0000-000000000901', :'userUnverifiedID', 'email-verification', :'templateEmailVerificationID', '2025-01-01 00:00:08');
select is(
    (select notification_id from get_pending_notification()),
    '00000000-0000-0000-0000-000000000901'::uuid,
    'Email verification notification for unverified user IS returned'
);
delete from notification where notification_id = '00000000-0000-0000-0000-000000000901';

-- Reset for attachment tests
update notification set processed = false where notification_id = :'notificationEventPublishedID';

-- Should return NULL attachment_ids when notification has no attachments
select is(
    (select attachment_ids from get_pending_notification()),
    null::uuid[],
    'Returns NULL attachment_ids when notification has no attachments'
);

-- Should return attachment_ids array when notification has attachments (sorted)
update notification set processed = true where notification_id = :'notificationEventPublishedID';
update notification set processed = true where notification_id = :'notificationGroupWelcomeID';
update notification set processed = false where notification_id = :'notificationWithAttachmentsID';
select is(
    (select attachment_ids from get_pending_notification()),
    array[:'attachmentID1', :'attachmentID2']::uuid[],
    'Returns attachment_ids array when notification has attachments (sorted)'
);

-- Reset for notification kind tests
update notification set processed = false where notification_id in (
    :'notificationEventPublishedID',
    :'notificationGroupWelcomeID'
);
update notification set processed = true where notification_id = :'notificationWithAttachmentsID';

-- Should work for group-welcome notification (verified user)
update notification set processed = true where notification_id = :'notificationEventPublishedID';
select is(
    (select kind from get_pending_notification()),
    'group-welcome',
    'Works for group-welcome notification (verified user)'
);

-- Should work for event-published notification (verified user)
update notification set processed = false where notification_id = :'notificationEventPublishedID';
update notification set processed = true where notification_id = :'notificationGroupWelcomeID';
select is(
    (select kind from get_pending_notification()),
    'event-published',
    'Works for event-published notification (verified user)'
);

-- Should block group-welcome for unverified user
update notification set processed = true where user_id = :'userVerifiedID';
update notification set processed = false where notification_id = :'notificationUnverifiedGroupWelcomeID';
select is(
    (select notification_id from get_pending_notification()),
    null::uuid,
    'Blocks group-welcome for unverified user'
);

-- Should block event-published for unverified user
update notification set processed = false where notification_id = :'notificationUnverifiedEventPublishedID';
select is(
    (select notification_id from get_pending_notification()),
    null::uuid,
    'Blocks event-published for unverified user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
