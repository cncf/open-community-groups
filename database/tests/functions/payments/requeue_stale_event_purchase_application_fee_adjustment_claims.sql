-- Tests recovery of application-fee adjustment claims abandoned by interrupted workers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd7440000-0000-0000-0000-000000000001'
\set completedAdjustmentID 'd7440000-0000-0000-0000-000000000002'
\set completedPurchaseID 'd7440000-0000-0000-0000-000000000003'
\set completedUserID 'd7440000-0000-0000-0000-000000000026'
\set eventCategoryID 'd7440000-0000-0000-0000-000000000004'
\set eventID 'd7440000-0000-0000-0000-000000000005'
\set failedAdjustmentID 'd7440000-0000-0000-0000-000000000006'
\set failedPurchaseID 'd7440000-0000-0000-0000-000000000007'
\set failedUserID 'd7440000-0000-0000-0000-000000000027'
\set finalAdjustmentID 'd7440000-0000-0000-0000-000000000008'
\set finalClaimID 'd7440000-0000-0000-0000-000000000009'
\set finalPriorAdjustmentID 'd7440000-0000-0000-0000-000000000010'
\set finalPriorClaimID 'd7440000-0000-0000-0000-000000000011'
\set finalPriorPurchaseID 'd7440000-0000-0000-0000-000000000012'
\set finalPriorUserID 'd7440000-0000-0000-0000-000000000028'
\set finalPurchaseID 'd7440000-0000-0000-0000-000000000013'
\set finalUserID 'd7440000-0000-0000-0000-000000000029'
\set groupCategoryID 'd7440000-0000-0000-0000-000000000014'
\set groupID 'd7440000-0000-0000-0000-000000000015'
\set recentAdjustmentID 'd7440000-0000-0000-0000-000000000016'
\set recentClaimID 'd7440000-0000-0000-0000-000000000017'
\set recentPurchaseID 'd7440000-0000-0000-0000-000000000018'
\set recentUserID 'd7440000-0000-0000-0000-000000000030'
\set staleAdjustmentID 'd7440000-0000-0000-0000-000000000019'
\set staleClaimID 'd7440000-0000-0000-0000-000000000020'
\set stalePriorAdjustmentID 'd7440000-0000-0000-0000-000000000021'
\set stalePriorClaimID 'd7440000-0000-0000-0000-000000000022'
\set stalePriorPurchaseID 'd7440000-0000-0000-0000-000000000023'
\set stalePriorUserID 'd7440000-0000-0000-0000-000000000031'
\set stalePurchaseID 'd7440000-0000-0000-0000-000000000024'
\set staleUserID 'd7440000-0000-0000-0000-000000000032'
\set ticketTypeID 'd7440000-0000-0000-0000-000000000025'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the recovery fixtures
insert into community (
    banner_mobile_url, banner_url, community_id, description, display_name,
    logo_url, name
) values (
    'https://example.test/mobile.png', 'https://example.test/banner.png',
    :'communityID', 'Community', 'Community', 'https://example.test/logo.png',
    'stale-application-fee-adjustment-community'
);

-- Event category used by the recovery event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the recovery group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the recovery event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Users owning the recovery purchases
insert into "user" (auth_hash, email, user_id, username) values
    ('completed-user', 'completed@example.test', :'completedUserID', 'completed-user'),
    ('failed-user', 'failed@example.test', :'failedUserID', 'failed-user'),
    ('final-prior-user', 'final-prior@example.test', :'finalPriorUserID', 'final-prior-user'),
    ('final-user', 'final@example.test', :'finalUserID', 'final-user'),
    ('recent-user', 'recent@example.test', :'recentUserID', 'recent-user'),
    ('stale-prior-user', 'stale-prior@example.test', :'stalePriorUserID', 'stale-prior-user'),
    ('stale-user', 'stale@example.test', :'staleUserID', 'stale-user');

-- Event associated with the recovery purchases
insert into event (
    description, event_category_id, event_id, event_kind_id, group_id, name,
    payment_currency_code, slug, timezone
) values (
    'Event', :'eventCategoryID', :'eventID', 'in-person', :'groupID', 'Event',
    'USD', 'event', 'UTC'
);

-- Ticket type snapshotted by every recovery purchase
insert into event_ticket_type (
    event_id, event_ticket_type_id, "order", seats_total, title
) values (:'eventID', :'ticketTypeID', 1, 20, 'General admission');

-- Purchases providing immutable context for every recovery state
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_object_account_id,
    provider_payment_reference, provider_total_minor,
    provisional_platform_fee_amount_minor, seller_snapshot, status,
    subtotal_excluding_tax_minor, tax_amount_minor, tax_behavior,
    tax_calculation_mode, tax_classification, ticket_title, user_id,
    venue_snapshot
) values
    (2500, 'direct-charge', 'acct_recovery', 'USD', :'eventID', :'completedPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_completed', 'ch_completed', 'cs_completed', 'acct_recovery', 'pi_completed', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'completedUserID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_recovery', 'USD', :'eventID', :'failedPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_failed', 'ch_failed', 'cs_failed', 'acct_recovery', 'pi_failed', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'failedUserID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_recovery', 'USD', :'eventID', :'finalPriorPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_final_prior', 'ch_final_prior', 'cs_final_prior', 'acct_recovery', 'pi_final_prior', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'finalPriorUserID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_recovery', 'USD', :'eventID', :'finalPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_final', 'ch_final', 'cs_final', 'acct_recovery', 'pi_final', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'finalUserID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_recovery', 'USD', :'eventID', :'recentPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_recent', 'ch_recent', 'cs_recent', 'acct_recovery', 'pi_recent', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'recentUserID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_recovery', 'USD', :'eventID', :'stalePriorPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_stale_prior', 'ch_stale_prior', 'cs_stale_prior', 'acct_recovery', 'pi_stale_prior', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'stalePriorUserID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_recovery', 'USD', :'eventID', :'stalePurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_stale', 'ch_stale', 'cs_stale', 'acct_recovery', 'pi_stale', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'staleUserID', '{}'::jsonb);

-- Application-fee adjustments covering recovery and protected states
insert into event_purchase_application_fee_adjustment (
    event_purchase_application_fee_adjustment_id, amount_minor, attempt_count,
    created_at, event_purchase_id, idempotency_key, kind, next_attempt_at,
    status, updated_at,

    claim_id, claimed_at, completed_at, failure_message,
    provider_application_fee_refund_id
) values
    (:'completedAdjustmentID', 80, 10, '2024-01-01 00:00:00+00', :'completedPurchaseID', 'recover-fee-completed', 'purchase-refund', '2024-01-01 00:00:00+00', 'completed', '2024-01-01 00:00:00+00', null, null, '2024-01-02 00:00:00+00', null, 'fr_completed'),
    (:'failedAdjustmentID', 80, 2, '2024-01-01 00:00:00+00', :'failedPurchaseID', 'recover-fee-failed', 'purchase-refund', '2024-01-01 00:00:00+00', 'failed', '2024-01-01 00:00:00+00', null, null, null, 'retry later', null),
    (:'finalAdjustmentID', 80, 10, '2024-01-01 00:00:00+00', :'finalPurchaseID', 'recover-fee-final', 'purchase-refund', '2024-01-01 00:00:00+00', 'processing', '2024-01-01 00:00:00+00', :'finalClaimID', current_timestamp - interval '16 minutes', null, null, null),
    (:'finalPriorAdjustmentID', 80, 10, '2024-01-01 00:00:00+00', :'finalPriorPurchaseID', 'recover-fee-final-prior', 'purchase-refund', '2024-01-01 00:00:00+00', 'processing', '2024-01-01 00:00:00+00', :'finalPriorClaimID', current_timestamp - interval '16 minutes', null, 'provider timed out', null),
    (:'recentAdjustmentID', 80, 2, '2024-01-01 00:00:00+00', :'recentPurchaseID', 'recover-fee-recent', 'purchase-refund', '2024-01-01 00:00:00+00', 'processing', '2024-01-01 00:00:00+00', :'recentClaimID', current_timestamp - interval '14 minutes', null, null, null),
    (:'staleAdjustmentID', 80, 2, '2024-01-01 00:00:00+00', :'stalePurchaseID', 'recover-fee-stale', 'purchase-refund', '2024-01-01 00:00:00+00', 'processing', '2024-01-01 00:00:00+00', :'staleClaimID', current_timestamp - interval '16 minutes', null, null, null),
    (:'stalePriorAdjustmentID', 80, 3, '2024-01-01 00:00:00+00', :'stalePriorPurchaseID', 'recover-fee-stale-prior', 'purchase-refund', '2024-01-01 00:00:00+00', 'processing', '2024-01-01 00:00:00+00', :'stalePriorClaimID', current_timestamp - interval '16 minutes', null, 'provider unavailable', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release every stale application-fee adjustment claim
select is(
    requeue_stale_event_purchase_application_fee_adjustment_claims(),
    4,
    'Should release every stale application-fee adjustment claim'
);

-- Should leave non-processing and completed adjustments unchanged
select results_eq(
    format($$
        select event_purchase_application_fee_adjustment_id, failure_message,
            status
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id in (%L::uuid, %L::uuid)
        order by event_purchase_application_fee_adjustment_id
    $$, :'completedAdjustmentID', :'failedAdjustmentID'),
    format($$ values
        (%L::uuid, null::text, 'completed'::text),
        (%L::uuid, 'retry later'::text, 'failed'::text)
    $$, :'completedAdjustmentID', :'failedAdjustmentID'),
    'Should leave non-processing and completed adjustments unchanged'
);

-- Should leave a recent processing claim unchanged
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message, next_attempt_at, status,
            updated_at
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'recentAdjustmentID'),
    format($$ values (
        %L::uuid,
        current_timestamp - interval '14 minutes',
        null::text,
        '2024-01-01 00:00:00+00'::timestamptz,
        'processing'::text,
        '2024-01-01 00:00:00+00'::timestamptz
    ) $$, :'recentClaimID'),
    'Should leave a recent processing claim unchanged'
);

-- Should preserve an existing failure below the attempt limit
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message,
            next_attempt_at = current_timestamp, status,
            updated_at = current_timestamp
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'stalePriorAdjustmentID'),
    $$ values (null::uuid, null::timestamptz, 'provider unavailable'::text, true, 'failed'::text, true) $$,
    'Should preserve an existing failure below the attempt limit'
);

-- Should preserve provider failure context on the final attempt
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message, status,
            updated_at = current_timestamp
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'finalPriorAdjustmentID'),
    $$ values (
        null::uuid,
        null::timestamptz,
        E'provider timed out\nApplication-fee adjustment worker claim expired after the final automatic attempt; provider outcome is unknown'::text,
        'failed'::text,
        true
    ) $$,
    'Should preserve provider failure context on the final attempt'
);

-- Should record final-attempt expiration when no provider failure exists
select results_eq(
    format($$
        select failure_message, next_attempt_at, status
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'finalAdjustmentID'),
    $$ values (
        'Application-fee adjustment worker claim expired after the final automatic attempt; provider outcome is unknown'::text,
        '2024-01-01 00:00:00+00'::timestamptz,
        'failed'::text
    ) $$,
    'Should record final-attempt expiration when no provider failure exists'
);

-- Should record worker expiration below the attempt limit
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message,
            next_attempt_at = current_timestamp, status,
            updated_at = current_timestamp
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'staleAdjustmentID'),
    $$ values (
        null::uuid,
        null::timestamptz,
        'Application-fee adjustment worker claim expired'::text,
        true,
        'failed'::text,
        true
    ) $$,
    'Should record worker expiration below the attempt limit'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
