-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attachmentID1 '00000000-0000-0000-0000-000000000501'
\set attachmentID2 '00000000-0000-0000-0000-000000000502'
\set notificationAlreadyClaimedID '00000000-0000-0000-0000-000000000101'
\set notificationAlreadyProcessedID '00000000-0000-0000-0000-000000000102'
\set notificationAttachmentID '00000000-0000-0000-0000-000000000103'
\set notificationEmailVerificationID '00000000-0000-0000-0000-000000000104'
\set notificationEventPublishedID '00000000-0000-0000-0000-000000000105'
\set notificationGroupWelcomeID '00000000-0000-0000-0000-000000000106'
\set notificationRetryID '00000000-0000-0000-0000-000000000107'
\set notificationUnverifiedEmailVerificationID '00000000-0000-0000-0000-000000000108'
\set notificationUnverifiedEventPublishedID '00000000-0000-0000-0000-000000000109'
\set notificationUnverifiedGroupWelcomeID '00000000-0000-0000-0000-000000000110'
\set templateEmailVerificationID '00000000-0000-0000-0000-000000000301'
\set templateEventPublishedID '00000000-0000-0000-0000-000000000302'
\set templateGroupWelcomeID '00000000-0000-0000-0000-000000000303'
\set userUnverifiedID '00000000-0000-0000-0000-000000000201'
\set userVerifiedID '00000000-0000-0000-0000-000000000202'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (auth_hash, email, email_verified, user_id, username) values
    ('hash1', 'verified@example.com', true, :'userVerifiedID', 'verified'),
    ('hash2', 'unverified@example.com', false, :'userUnverifiedID', 'unverified');

-- Notification templates
insert into notification_template_data (data, hash, notification_template_data_id) values
    ('{"link": "https://example.com/verify"}'::jsonb, 'hash_email_verification', :'templateEmailVerificationID'),
    ('{"event": "test"}'::jsonb, 'hash_event_published', :'templateEventPublishedID'),
    ('{"group": "test"}'::jsonb, 'hash_group_welcome', :'templateGroupWelcomeID');

-- Notifications that should be skipped before the first eligible row
insert into notification (
    created_at,
    delivery_attempts,
    delivery_claimed_at,
    delivery_status,
    kind,
    notification_id,
    processed_at,
    user_id
) values
    (
        '2025-01-01 00:00:01',
        1,
        current_timestamp,
        'processing',
        'group-welcome',
        :'notificationAlreadyClaimedID',
        null,
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:02',
        1,
        null,
        'processed',
        'group-welcome',
        :'notificationAlreadyProcessedID',
        current_timestamp,
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:03',
        0,
        null,
        'pending',
        'group-welcome',
        :'notificationUnverifiedGroupWelcomeID',
        null,
        :'userUnverifiedID'
    ),
    (
        '2025-01-01 00:00:04',
        0,
        null,
        'pending',
        'event-published',
        :'notificationUnverifiedEventPublishedID',
        null,
        :'userUnverifiedID'
    );

-- Notifications claimed by the tests in FIFO order
insert into notification (
    created_at,
    delivery_attempts,
    delivery_status,
    kind,
    notification_id,
    notification_template_data_id,
    user_id
) values
    (
        '2025-01-01 00:00:05',
        0,
        'pending',
        'email-verification',
        :'notificationEmailVerificationID',
        :'templateEmailVerificationID',
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:06',
        0,
        'pending',
        'group-welcome',
        :'notificationGroupWelcomeID',
        :'templateGroupWelcomeID',
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:07',
        0,
        'pending',
        'event-published',
        :'notificationEventPublishedID',
        :'templateEventPublishedID',
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:08',
        0,
        'pending',
        'event-welcome',
        :'notificationAttachmentID',
        null,
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:09',
        1,
        'pending',
        'group-welcome',
        :'notificationRetryID',
        :'templateGroupWelcomeID',
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:10',
        0,
        'pending',
        'email-verification',
        :'notificationUnverifiedEmailVerificationID',
        :'templateEmailVerificationID',
        :'userUnverifiedID'
    );

-- Notification attachments
insert into attachment (attachment_id, content_type, data, file_name, hash) values
    (:'attachmentID1', 'text/calendar', 'BEGIN:VCALENDAR'::bytea, 'event.ics', 'hash1'),
    (:'attachmentID2', 'application/pdf', 'PDF'::bytea, 'ticket.pdf', 'hash2');
insert into notification_attachment (attachment_id, notification_id) values
    (:'attachmentID1', :'notificationAttachmentID'),
    (:'attachmentID2', :'notificationAttachmentID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Skipped before the first claim: processing, processed, and unverified-user rows
-- Should skip non-deliverable rows and claim the first eligible notification
select is(
    (select row_to_json(r)::jsonb from claim_pending_notification() r),
    jsonb_build_object(
        'attachment_ids', null,
        'email', 'verified@example.com',
        'kind', 'email-verification',
        'notification_id', :'notificationEmailVerificationID',
        'template_data', '{"link": "https://example.com/verify"}'::jsonb
    ),
    'Skips non-deliverable rows and returns all expected fields'
);

-- Should store claim state on the claimed notification
select results_eq(
    $$
        select
            delivery_attempts,
            delivery_claimed_at is not null,
            delivery_status
        from notification
        where notification_id = '00000000-0000-0000-0000-000000000104'
    $$,
    $$ values (1, true, 'processing'::text) $$,
    'Stores claim state on claimed notification'
);

-- The email-verification row is now processing; the next claim should move forward
-- Should claim group-welcome notifications for verified users
select is(
    (select row_to_json(r)::jsonb from claim_pending_notification() r),
    jsonb_build_object(
        'attachment_ids', null,
        'email', 'verified@example.com',
        'kind', 'group-welcome',
        'notification_id', :'notificationGroupWelcomeID',
        'template_data', '{"group": "test"}'::jsonb
    ),
    'Claims group-welcome notification for verified user'
);

-- The group-welcome row is now processing; the next verified row is event-published
-- Should claim event-published notifications for verified users
select is(
    (select row_to_json(r)::jsonb from claim_pending_notification() r),
    jsonb_build_object(
        'attachment_ids', null,
        'email', 'verified@example.com',
        'kind', 'event-published',
        'notification_id', :'notificationEventPublishedID',
        'template_data', '{"event": "test"}'::jsonb
    ),
    'Claims event-published notification for verified user'
);

-- The next claim is the attachment notification, so assert its id and attachments
-- Should return sorted attachment ids
select is(
    (select row_to_json(r)::jsonb from claim_pending_notification() r),
    jsonb_build_object(
        'attachment_ids', array[:'attachmentID1', :'attachmentID2']::uuid[],
        'email', 'verified@example.com',
        'kind', 'event-welcome',
        'notification_id', :'notificationAttachmentID',
        'template_data', null
    ),
    'Claims attachment notification and returns sorted attachment ids'
);

-- The attachment row is now processing; the next row has one previous attempt
-- Should claim a previously attempted pending notification
select is(
    (select notification_id from claim_pending_notification()),
    :'notificationRetryID'::uuid,
    'Claims a previously attempted pending notification'
);

-- Should increment attempts on claim
select is(
    (select delivery_attempts from notification where notification_id = :'notificationRetryID'),
    2,
    'Increments delivery attempts on claim'
);

-- Should return email verification notifications for unverified users
select is(
    (select notification_id from claim_pending_notification()),
    :'notificationUnverifiedEmailVerificationID'::uuid,
    'Claims email verification notification for unverified user'
);

-- Should leave other notification kinds for unverified users pending
select results_eq(
    $$
        select notification_id
        from notification
        where user_id = '00000000-0000-0000-0000-000000000201'
        and delivery_status = 'pending'
        order by notification_id
    $$,
    $$
        values
            ('00000000-0000-0000-0000-000000000109'::uuid),
            ('00000000-0000-0000-0000-000000000110'::uuid)
    $$,
    'Leaves other notification kinds for unverified users pending'
);

-- Should return NULL when no deliverable pending notifications exist
select is(
    (select notification_id from claim_pending_notification()),
    null::uuid,
    'Returns NULL when no deliverable pending notifications exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
