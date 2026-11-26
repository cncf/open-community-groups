-- Tests marking stale processing notifications with an unknown delivery outcome.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notificationFreshProcessingID '8a040000-0000-0000-0000-000000000001'
\set notificationPendingID '8a040000-0000-0000-0000-000000000002'
\set notificationProcessedID '8a040000-0000-0000-0000-000000000003'
\set notificationStalePasswordResetID '8a040000-0000-0000-0000-000000000006'
\set notificationStaleProcessingID '8a040000-0000-0000-0000-000000000004'
\set stalePasswordResetTemplateDataID '8a040000-0000-0000-0000-000000000007'
\set userID '8a040000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Template data for a stale password-reset notification scrubbed during timeout recovery
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'stalePasswordResetTemplateDataID',
    '{"link":"https://example.test/reset-password/8a04-stale"}'::jsonb,
    encode(digest('8a04-stale-password-reset-payload', 'sha256'), 'hex')
);

-- User
select fx_user(:'userID', jsonb_build_object('username', 'user-mark-stale-processing-notifications-unknown'));

-- Notifications
insert into notification (
    delivery_claimed_at,
    delivery_status,
    kind,
    notification_id,
    notification_template_data_id,
    processed_at,
    user_id
) values
    (
        current_timestamp - interval '5 minutes',
        'processing',
        'group-welcome',
        :'notificationFreshProcessingID',
        null,
        null,
        :'userID'
    ),
    (
        current_timestamp - interval '30 minutes',
        'pending',
        'group-welcome',
        :'notificationPendingID',
        null,
        null,
        :'userID'
    ),
    (
        current_timestamp - interval '30 minutes',
        'processed',
        'group-welcome',
        :'notificationProcessedID',
        null,
        current_timestamp - interval '30 minutes',
        :'userID'
    ),
    (
        current_timestamp - interval '30 minutes',
        'processing',
        'password-reset',
        :'notificationStalePasswordResetID',
        :'stalePasswordResetTemplateDataID',
        null,
        :'userID'
    ),
    (
        current_timestamp - interval '30 minutes',
        'processing',
        'group-welcome',
        :'notificationStaleProcessingID',
        null,
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
    2,
    'Should mark only stale processing notifications'
);

-- Should persist delivery-unknown state for stale claims
select results_eq(
    format(
        $$
        select
            delivery_status,
            error,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationStaleProcessingID'
    ),
    $$
        values (
            'delivery-unknown'::text,
            'delivery outcome unknown after processing timeout'::text,
            current_timestamp
        )
    $$,
    'Should persist delivery-unknown state for stale claims'
);

-- Should leave fresh processing notifications active
select results_eq(
    format(
        $$
        select
            delivery_status,
            processed_at
        from notification
        where notification_id = %L::uuid
        $$,
        :'notificationFreshProcessingID'
    ),
    $$ values ('processing'::text, null::timestamptz) $$,
    'Should leave fresh processing notifications active'
);

-- Should leave other delivery statuses unchanged
select results_eq(
    format(
        $$
        select
            notification_id,
            delivery_status
        from notification
        where notification_id in (
            %L::uuid,
            %L::uuid
        )
        order by notification_id
        $$,
        :'notificationPendingID',
        :'notificationProcessedID'
    ),
    format(
        $$
        values
            (%L::uuid, 'pending'::text),
            (%L::uuid, 'processed'::text)
        $$,
        :'notificationPendingID',
        :'notificationProcessedID'
    ),
    'Should leave other delivery statuses unchanged'
);

-- Should detach and delete template data for stale password-reset notifications
select is(
    (
        select notification_template_data_id
        from notification
        where notification_id = :'notificationStalePasswordResetID'::uuid
    ),
    null::uuid,
    'Should detach template data from stale password-reset notifications'
);
select is(
    (
        select count(*)::int
        from notification_template_data
        where notification_template_data_id = :'stalePasswordResetTemplateDataID'::uuid
    ),
    0,
    'Should delete unreferenced password-reset template data on stale claim recovery'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
