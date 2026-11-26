-- Tests scrubbing stored password-reset notification payloads and canceling pending deliveries.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notifOtherKindID '0a170000-0000-0000-0000-000000000021'
\set notifPendingID '0a170000-0000-0000-0000-000000000022'
\set notifProcessedID '0a170000-0000-0000-0000-000000000023'
\set notifProcessingID '0a170000-0000-0000-0000-000000000024'
\set tplOtherKindID '0a170000-0000-0000-0000-000000000011'
\set tplPendingID '0a170000-0000-0000-0000-000000000012'
\set tplProcessedID '0a170000-0000-0000-0000-000000000013'
\set tplProcessingID '0a170000-0000-0000-0000-000000000014'
\set userID '0a170000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User whose password-reset notifications are scrubbed
select fx_user(:'userID');

-- Template data for an unrelated notification kind that must remain untouched
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'tplOtherKindID',
    '{"link":"https://example.test/verify-email/keep"}'::jsonb,
    encode(digest('0a17-other-kind', 'sha256'), 'hex')
);

-- Template data for a pending password-reset notification to cancel and delete
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'tplPendingID',
    '{"link":"https://example.test/reset-password/pending-secret"}'::jsonb,
    encode(digest('0a17-pending', 'sha256'), 'hex')
);

-- Template data for an already processed password-reset notification to detach and delete
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'tplProcessedID',
    '{"link":"https://example.test/reset-password/processed-secret"}'::jsonb,
    encode(digest('0a17-processed', 'sha256'), 'hex')
);

-- Template data for an in-flight processing password-reset notification left for update_notification
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'tplProcessingID',
    '{"link":"https://example.test/reset-password/processing-secret"}'::jsonb,
    encode(digest('0a17-processing', 'sha256'), 'hex')
);

-- Non-password-reset notification that must remain untouched
insert into notification (notification_id, delivery_status, kind, notification_template_data_id, user_id)
values (:'notifOtherKindID', 'pending', 'email-verification', :'tplOtherKindID', :'userID');

-- Pending password-reset notification that must be canceled and scrubbed
insert into notification (
    notification_id,
    delivery_status,
    kind,
    next_delivery_attempt_at,
    notification_template_data_id,
    user_id
)
values (
    :'notifPendingID',
    'pending',
    'password-reset',
    current_timestamp + interval '5 minutes',
    :'tplPendingID',
    :'userID'
);

-- Processed password-reset notification whose stored payload must be detached and removed
insert into notification (
    notification_id,
    delivery_status,
    kind,
    notification_template_data_id,
    processed_at,
    user_id
)
values (
    :'notifProcessedID',
    'processed',
    'password-reset',
    :'tplProcessedID',
    current_timestamp - interval '5 minutes',
    :'userID'
);

-- Processing password-reset notification left untouched while actively claimed
insert into notification (
    notification_id,
    delivery_claimed_at,
    delivery_status,
    kind,
    notification_template_data_id,
    user_id
)
values (
    :'notifProcessingID',
    current_timestamp,
    'processing',
    'password-reset',
    :'tplProcessingID',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should handle null and empty user arrays cleanly
select lives_ok(
    $$select purge_password_reset_notification_data(null)$$,
    'Should accept a null user id array'
);
select lives_ok(
    $$select purge_password_reset_notification_data('{}'::uuid[])$$,
    'Should accept an empty user id array'
);

-- Should scrub pending and processed password-reset payloads without touching processing or other kinds
select lives_ok(
    format($$select purge_password_reset_notification_data(array[%L::uuid])$$, :'userID'),
    'Should purge password-reset notification payloads for the user'
);

-- Should cancel the pending password-reset notification and clear its template link
select results_eq(
    format(
        $$
            select
                delivery_status,
                error,
                next_delivery_attempt_at is null,
                notification_template_data_id is null,
                processed_at is not null
            from notification
            where notification_id = %L::uuid
        $$,
        :'notifPendingID'
    ),
    $$values ('failed'::text, 'password reset token no longer active'::text, true, true, true)$$,
    'Should cancel pending password-reset notifications and detach template data'
);

-- Should keep processed status while detaching stored template data
select results_eq(
    format(
        $$
            select delivery_status, notification_template_data_id is null
            from notification
            where notification_id = %L::uuid
        $$,
        :'notifProcessedID'
    ),
    $$values ('processed'::text, true)$$,
    'Should preserve processed status while detaching template data'
);

-- Should leave processing and unrelated notifications intact
select results_eq(
    format(
        $$
            select notification_id, delivery_status, notification_template_data_id
            from notification
            where notification_id in (%L::uuid, %L::uuid)
            order by notification_id
        $$,
        :'notifOtherKindID',
        :'notifProcessingID'
    ),
    format(
        $$
            values
                (%L::uuid, 'pending'::text, %L::uuid),
                (%L::uuid, 'processing'::text, %L::uuid)
        $$,
        :'notifOtherKindID',
        :'tplOtherKindID',
        :'notifProcessingID',
        :'tplProcessingID'
    ),
    'Should leave processing and unrelated notifications intact'
);

-- Should delete unreferenced password-reset template data rows and retain active ones
select results_eq(
    format(
        $$
            select notification_template_data_id
            from notification_template_data
            where notification_template_data_id in (%L::uuid, %L::uuid, %L::uuid, %L::uuid)
            order by notification_template_data_id
        $$,
        :'tplOtherKindID',
        :'tplPendingID',
        :'tplProcessedID',
        :'tplProcessingID'
    ),
    format(
        $$values (%L::uuid), (%L::uuid)$$,
        :'tplOtherKindID',
        :'tplProcessingID'
    ),
    'Should delete only scrubbed unreferenced password-reset template data rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
