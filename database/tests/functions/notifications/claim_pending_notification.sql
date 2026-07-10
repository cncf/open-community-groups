-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attachmentID1 '8a010000-0000-0000-0000-000000000001'
\set attachmentID2 '8a010000-0000-0000-0000-000000000002'
\set notificationAlreadyClaimedID '8a010000-0000-0000-0000-000000000003'
\set notificationAlreadyProcessedID '8a010000-0000-0000-0000-000000000004'
\set notificationAttachmentID '8a010000-0000-0000-0000-000000000005'
\set notificationEmailVerificationID '8a010000-0000-0000-0000-000000000006'
\set notificationEventPublishedID '8a010000-0000-0000-0000-000000000007'
\set notificationFutureRetryID '8a010000-0000-0000-0000-000000000023'
\set notificationGroupWelcomeID '8a010000-0000-0000-0000-000000000008'
\set notificationPreRegisteredEventInvitationID '8a010000-0000-0000-0000-000000000009'
\set notificationPreRegisteredGroupWelcomeID '8a010000-0000-0000-0000-000000000010'
\set notificationPreRegisteredVerifiedGroupWelcomeID '8a010000-0000-0000-0000-000000000011'
\set notificationRetryID '8a010000-0000-0000-0000-000000000012'
\set notificationUnverifiedEmailVerificationID '8a010000-0000-0000-0000-000000000013'
\set notificationUnverifiedEventPublishedID '8a010000-0000-0000-0000-000000000014'
\set notificationUnverifiedGroupWelcomeID '8a010000-0000-0000-0000-000000000015'
\set templateEmailVerificationID '8a010000-0000-0000-0000-000000000016'
\set templateEventPublishedID '8a010000-0000-0000-0000-000000000017'
\set templateGroupWelcomeID '8a010000-0000-0000-0000-000000000018'
\set userPreRegisteredID '8a010000-0000-0000-0000-000000000019'
\set userPreRegisteredVerifiedID '8a010000-0000-0000-0000-000000000020'
\set userUnverifiedID '8a010000-0000-0000-0000-000000000021'
\set userVerifiedID '8a010000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    registration_status
) values
    (:'userVerifiedID', 'hash1', 'verified@example.com', true, 'verified', 'registered'),
    (:'userUnverifiedID', 'hash2', 'unverified@example.com', false, 'unverified', 'registered'),
    (:'userPreRegisteredID', 'hash3', 'invited@example.com', false, 'invited', 'pre-registered'),
    (:'userPreRegisteredVerifiedID', 'hash4', 'verified-invited@example.com',
        true, 'verified-invited', 'pre-registered');

-- Notification templates
insert into notification_template_data (data, hash, notification_template_data_id) values
    (
        '{"link": "https://example.com/verify"}'::jsonb,
        'hash_email_verification',
        :'templateEmailVerificationID'
    ),
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
        '2025-01-01 00:00:04.5',
        0,
        null,
        'pending',
        'event-published',
        :'notificationUnverifiedEventPublishedID',
        null,
        :'userUnverifiedID'
    ),
    (
        '2025-01-01 00:00:04',
        0,
        null,
        'pending',
        'group-welcome',
        :'notificationPreRegisteredVerifiedGroupWelcomeID',
        null,
        :'userPreRegisteredVerifiedID'
    );

-- Notifications claimed by the tests in FIFO order
insert into notification (
    created_at,
    delivery_attempts,
    delivery_status,
    kind,
    next_delivery_attempt_at,
    notification_id,
    notification_template_data_id,
    user_id
) values
    (
        '2025-01-01 00:00:05',
        0,
        'pending',
        'email-verification',
        null,
        :'notificationEmailVerificationID',
        :'templateEmailVerificationID',
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:06',
        0,
        'pending',
        'group-welcome',
        null,
        :'notificationGroupWelcomeID',
        :'templateGroupWelcomeID',
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:07',
        0,
        'pending',
        'event-published',
        null,
        :'notificationEventPublishedID',
        :'templateEventPublishedID',
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:08',
        0,
        'pending',
        'event-welcome',
        null,
        :'notificationAttachmentID',
        null,
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:08.5',
        1,
        'pending',
        'group-welcome',
        current_timestamp + interval '1 hour',
        :'notificationFutureRetryID',
        :'templateGroupWelcomeID',
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:09',
        1,
        'pending',
        'group-welcome',
        null,
        :'notificationRetryID',
        :'templateGroupWelcomeID',
        :'userVerifiedID'
    ),
    (
        '2025-01-01 00:00:10',
        0,
        'pending',
        'email-verification',
        null,
        :'notificationUnverifiedEmailVerificationID',
        :'templateEmailVerificationID',
        :'userUnverifiedID'
    ),
    (
        '2025-01-01 00:00:11',
        0,
        'pending',
        'event-invitation',
        null,
        :'notificationPreRegisteredEventInvitationID',
        :'templateEventPublishedID',
        :'userPreRegisteredID'
    ),
    (
        '2025-01-01 00:00:12',
        0,
        'pending',
        'group-welcome',
        null,
        :'notificationPreRegisteredGroupWelcomeID',
        :'templateGroupWelcomeID',
        :'userPreRegisteredID'
    );

-- Notification attachments
insert into attachment (attachment_id, content_type, data, file_name, hash) values
    (:'attachmentID1', 'text/calendar', 'BEGIN:VCALENDAR'::bytea, 'event.ics', 'hash1'),
    (:'attachmentID2', 'application/pdf', 'PDF'::bytea, 'ticket.pdf', 'hash2');

-- Attachment links returned with the claimed notification
insert into notification_attachment (attachment_id, notification_id) values
    (:'attachmentID1', :'notificationAttachmentID'),
    (:'attachmentID2', :'notificationAttachmentID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject non-positive delivery rate limits
select throws_ok(
    $$ select * from claim_pending_notification(0, 60) $$,
    'delivery rate limit must be positive',
    'Should reject non-positive delivery rate limits'
);

-- Should reject non-positive delivery rate limit windows
select throws_ok(
    $$ select * from claim_pending_notification(1, 0) $$,
    'delivery rate limit window must be positive',
    'Should reject non-positive delivery rate limit windows'
);

-- Should return NULL when the delivery rate limit has been exhausted
select is(
    (select notification_id from claim_pending_notification(1, 60)),
    null::uuid,
    'Returns NULL when delivery rate limit is exhausted'
);

-- Should not claim a pending notification while rate limited
select is(
    (
        select delivery_status
        from notification
        where notification_id = :'notificationEmailVerificationID'
    ),
    'pending',
    'Leaves pending notification unclaimed when delivery rate limit is exhausted'
);

-- Mark a claimed notification as stale for the next claim-selection scenario
update notification
set delivery_claimed_at = '2025-01-01 00:00:00+00'
where notification_id = :'notificationAlreadyClaimedID';

-- Skipped before the first claim: processing, processed, unverified-user, and pre-registered rows
-- Should skip non-deliverable rows and claim the first eligible notification
select is(
    (select row_to_json(r)::jsonb from claim_pending_notification(1, 60) r),
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
    format(
        $$
        select
            delivery_attempts,
            delivery_claimed_at is not null,
            delivery_status
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationEmailVerificationID'
    ),
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

-- Should skip scheduled retries that are not due
select is(
    (
        select delivery_status
        from notification
        where notification_id = :'notificationFutureRetryID'
    ),
    'pending',
    'Leaves future scheduled retry pending'
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

-- Should return event invitation notifications for pre-registered users
select is(
    (select row_to_json(r)::jsonb from claim_pending_notification() r),
    jsonb_build_object(
        'attachment_ids', null,
        'email', 'invited@example.com',
        'kind', 'event-invitation',
        'notification_id', :'notificationPreRegisteredEventInvitationID',
        'template_data', '{"event": "test"}'::jsonb
    ),
    'Claims event invitation notification for pre-registered user'
);

-- Should leave other notification kinds for unverified users pending
select results_eq(
    format(
        $$
        select notification_id
        from notification
        where user_id = %L::uuid
        and delivery_status = 'pending'
        order by notification_id
        $$,
        :'userUnverifiedID'
    ),
    format(
        $$
        values
            (%L::uuid),
            (%L::uuid)
        $$,
        :'notificationUnverifiedEventPublishedID',
        :'notificationUnverifiedGroupWelcomeID'
    ),
    'Leaves other notification kinds for unverified users pending'
);

-- Should leave other notification kinds for pre-registered users pending
select results_eq(
    format(
        $$
        select notification_id
        from notification
        where user_id = %L::uuid
        and delivery_status = 'pending'
        order by notification_id
        $$,
        :'userPreRegisteredID'
    ),
    format(
        $$ values (%L::uuid) $$,
        :'notificationPreRegisteredGroupWelcomeID'
    ),
    'Leaves other notification kinds for pre-registered users pending'
);

-- Should require regular registration before verified users receive regular notifications
select is(
    (
        select delivery_status
        from notification
        where notification_id = :'notificationPreRegisteredVerifiedGroupWelcomeID'
    ),
    'pending',
    'Leaves regular notifications pending for pre-registered users even when email is verified'
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
