-- Tests marking a claimed notification with an unknown delivery outcome.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationPasswordResetID '8a090000-0000-0000-0000-000000000005'
\set notificationProcessedID '8a090000-0000-0000-0000-000000000001'
\set notificationProcessingID '8a090000-0000-0000-0000-000000000002'
\set notificationStaleClaimID '8a090000-0000-0000-0000-000000000004'
\set passwordResetTemplateDataID '8a090000-0000-0000-0000-000000000006'
\set userID '8a090000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Template data for a password-reset notification scrubbed when marked unknown
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'passwordResetTemplateDataID',
    '{"link":"https://example.test/reset-password/8a09-secret"}'::jsonb,
    encode(digest('8a09-password-reset-payload', 'sha256'), 'hex')
);

-- User who owns the delivery notifications
select fx_user(:'userID', jsonb_build_object('username', 'user-mark-notification-delivery-unknown'));

-- Processing password-reset notification scrubbed when marked delivery-unknown
insert into notification (
    notification_id,
    delivery_attempts,
    delivery_status,
    kind,
    user_id,

    delivery_claimed_at,
    notification_template_data_id
) values (
    :'notificationPasswordResetID',
    1,
    'processing',
    'password-reset',
    :'userID',

    '2025-01-01 00:00:05+00',
    :'passwordResetTemplateDataID'
);

-- Processed notification rejected by the invalid-state scenario
insert into notification (
    notification_id,
    delivery_attempts,
    delivery_status,
    kind,
    user_id,

    processed_at
) values (
    :'notificationProcessedID',
    1,
    'processed',
    'event-welcome',
    :'userID',

    '2025-01-01 00:00:01+00'
);

-- Processing notification used by the unknown-outcome scenarios
insert into notification (
    notification_id,
    delivery_attempts,
    delivery_status,
    kind,
    user_id,

    delivery_claimed_at
) values (
    :'notificationProcessingID',
    2,
    'processing',
    'event-welcome',
    :'userID',

    '2025-01-01 00:00:02+00'
);

-- Processing notification with a newer claim than the stale worker holds
insert into notification (
    notification_id,
    delivery_attempts,
    delivery_status,
    kind,
    user_id,

    delivery_claimed_at
) values (
    :'notificationStaleClaimID',
    3,
    'processing',
    'event-welcome',
    :'userID',

    '2025-01-01 00:00:04+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mark a claimed notification with an unknown delivery outcome
select lives_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid,
            'network error: connection reset by peer',
            '2025-01-01 00:00:02+00'::timestamptz
        )$$,
        :'notificationProcessingID'
    ),
    'Should mark a claimed notification with an unknown delivery outcome'
);

-- Should persist the unknown outcome without changing claim metadata
select results_eq(
    format(
        $$
        select
            delivery_attempts,
            delivery_claimed_at,
            delivery_status,
            error,
            next_delivery_attempt_at,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationProcessingID'
    ),
    $$
        values (
            2,
            '2025-01-01 00:00:02+00'::timestamptz,
            'delivery-unknown'::text,
            'network error: connection reset by peer'::text,
            null::timestamptz,
            current_timestamp
        )
    $$,
    'Should persist the unknown outcome without changing claim metadata'
);

-- Should reject blank delivery errors
select throws_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid, ' ', '2025-01-01 00:00:02+00'::timestamptz
        )$$,
        :'notificationProcessingID'
    ),
    'P0001',
    'delivery error is required',
    'Should reject blank delivery errors'
);

-- Should reject notifications that are no longer being processed
select throws_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid, 'network error', '2025-01-01 00:00:01+00'::timestamptz
        )$$,
        :'notificationProcessedID'
    ),
    'P0001',
    'notification delivery claim not found or no longer active',
    'Should reject notifications that are no longer being processed'
);

-- Should reject null delivery errors
select throws_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid, null::text, '2025-01-01 00:00:02+00'::timestamptz
        )$$,
        :'notificationProcessingID'
    ),
    'P0001',
    'delivery error is required',
    'Should reject null delivery errors'
);

-- Should stop a stale worker from marking a newer delivery claim unknown
select throws_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid,
            'network error',
            '2025-01-01 00:00:03+00'::timestamptz
        )$$,
        :'notificationStaleClaimID'
    ),
    'P0001',
    'notification delivery claim not found or no longer active',
    'Should stop a stale worker from marking a newer delivery claim unknown'
);

-- Should scrub template data when marking a password-reset notification delivery-unknown
select lives_ok(
    format(
        $$select mark_notification_delivery_unknown(
            %L::uuid,
            'smtp timeout after data',
            '2025-01-01 00:00:05+00'::timestamptz
        )$$,
        :'notificationPasswordResetID'
    ),
    'Should mark a password-reset notification delivery-unknown'
);
select is(
    (
        select notification_template_data_id
        from notification
        where notification_id = :'notificationPasswordResetID'::uuid
    ),
    null::uuid,
    'Should detach template data from a delivery-unknown password-reset notification'
);
select is(
    (
        select count(*)::int
        from notification_template_data
        where notification_template_data_id = :'passwordResetTemplateDataID'::uuid
    ),
    0,
    'Should delete unreferenced password-reset template data on unknown outcome'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
