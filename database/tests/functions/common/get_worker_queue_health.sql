-- Tests worker queue backlog signals.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b0050000-0000-0000-0000-000000000001'
\set completedBadgeJobID 'b0050000-0000-0000-0000-000000000015'
\set eventCategoryID 'b0050000-0000-0000-0000-000000000002'
\set eventID 'b0050000-0000-0000-0000-000000000003'
\set groupCategoryID 'b0050000-0000-0000-0000-000000000004'
\set groupID 'b0050000-0000-0000-0000-000000000005'
\set pendingBadgeJobID 'b0050000-0000-0000-0000-000000000016'
\set pendingNotificationID 'b0050000-0000-0000-0000-000000000006'
\set processedNotificationID 'b0050000-0000-0000-0000-000000000007'
\set processingBadgeJobClaimID 'b0050000-0000-0000-0000-000000000017'
\set processingBadgeJobID 'b0050000-0000-0000-0000-000000000018'
\set processingJobClaimID 'b0050000-0000-0000-0000-000000000008'
\set processingJobID 'b0050000-0000-0000-0000-000000000009'
\set processingNotificationID 'b0050000-0000-0000-0000-000000000010'
\set purchaseID 'b0050000-0000-0000-0000-000000000011'
\set recentPendingNotificationID 'b0050000-0000-0000-0000-000000000012'
\set ticketTypeID 'b0050000-0000-0000-0000-000000000013'
\set userID 'b0050000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user, group, event and ticket type
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General admission'
));

-- Badge award jobs: one pending for two hours, one processing, one completed
insert into badge_award_job (
    badge_award_job_id,
    accepted_count,
    actor_username,
    awarded_count,
    badge_snapshot,
    community_id,
    created_at,
    group_id,
    next_recipient_offset,
    recipient_count,
    status,

    claim_id,
    claimed_at,
    completed_at
) values
    (:'pendingBadgeJobID', 1, 'queue-health-admin', 0, '{"name":"Pending"}', :'communityID',
        current_timestamp - interval '2 hours', :'groupID', 0, 1, 'pending', null, null, null),
    (:'processingBadgeJobID', 1, 'queue-health-admin', 0, '{"name":"Processing"}', :'communityID',
        current_timestamp - interval '3 hours', :'groupID', 0, 1, 'processing',
        :'processingBadgeJobClaimID', current_timestamp, null),
    (:'completedBadgeJobID', 1, 'queue-health-admin', 1, '{"name":"Completed"}', :'communityID',
        current_timestamp - interval '4 hours', :'groupID', 1, 1, 'completed', null, null,
        current_timestamp);

-- Purchase backing the processing payment job
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_charge_id, provider_checkout_session_id,
    provider_object_account_id, provider_payment_reference,
    provider_total_minor, provisional_platform_fee_amount_minor,
    seller_snapshot, status, subtotal_excluding_tax_minor, tax_amount_minor,
    tax_behavior, tax_calculation_mode, tax_classification, ticket_title,
    user_id, venue_snapshot
) values (
    2500, 'direct-charge', 'acct_b005', 'USD', :'eventID', :'purchaseID', :'ticketTypeID', 80,
    'stripe', 'ch_queue_health_b0050000', 'cs_queue_health_b0050000', 'acct_b005',
    'pi_queue_health_b0050000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb,
    'refund-pending', 2300, 200, 'inclusive', 'manual', 'professional-event-admission',
    'General admission', :'userID', '{}'::jsonb
);

-- Refund job claimed by a worker, leaving no pending payment jobs
insert into payment_job (
    claim_id, claimed_at, created_at, event_purchase_id, idempotency_key, kind,
    next_attempt_at, payment_job_id, payment_provider_id, status
) values (
    :'processingJobClaimID', current_timestamp, current_timestamp - interval '10 minutes',
    :'purchaseID', 'queue-health-processing-b0050000', 'event-purchase-refund',
    current_timestamp, :'processingJobID', 'stripe', 'processing'
);

-- Notifications: one pending for an hour, one recent pending, one processing, one processed
insert into notification (
    notification_id, created_at, delivery_attempts, delivery_claimed_at, delivery_status,
    kind, user_id
) values
    (:'pendingNotificationID', current_timestamp - interval '1 hour', 0, null, 'pending',
        'event-canceled', :'userID'),
    (:'recentPendingNotificationID', current_timestamp - interval '1 minute', 0, null,
        'pending', 'event-canceled', :'userID'),
    (:'processingNotificationID', current_timestamp - interval '2 hours', 1,
        current_timestamp, 'processing', 'event-canceled', :'userID'),
    (:'processedNotificationID', current_timestamp - interval '3 hours', 1, null,
        'processed', 'event-canceled', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count pending and processing badge award jobs and age the oldest pending one
select is(
    (
        select jsonb_build_object(
            'pending', (get_worker_queue_health()->'badge_award_jobs'->>'pending')::int,
            'processing', (get_worker_queue_health()->'badge_award_jobs'->>'processing')::int,
            'oldest_pending_age_minutes',
                (get_worker_queue_health()->'badge_award_jobs'->>'oldest_pending_age_secs')::int / 60
        )
    ),
    '{"pending": 1, "processing": 1, "oldest_pending_age_minutes": 120}'::jsonb,
    'Should count pending and processing badge award jobs and age the oldest pending one'
);

-- Should count pending and processing notifications and age the oldest pending one
select is(
    (
        select jsonb_build_object(
            'pending', (get_worker_queue_health()->'notifications'->>'pending')::int,
            'processing', (get_worker_queue_health()->'notifications'->>'processing')::int,
            'oldest_pending_age_minutes',
                (get_worker_queue_health()->'notifications'->>'oldest_pending_age_secs')::int / 60
        )
    ),
    '{"pending": 2, "processing": 1, "oldest_pending_age_minutes": 60}'::jsonb,
    'Should count pending and processing notifications and age the oldest pending one'
);

-- Should count processing payment jobs and report no age without pending ones
select is(
    (get_worker_queue_health()->'payment_jobs')::jsonb,
    '{"pending": 0, "processing": 1, "oldest_pending_age_secs": null}'::jsonb,
    'Should count processing payment jobs and report no age without pending ones'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
