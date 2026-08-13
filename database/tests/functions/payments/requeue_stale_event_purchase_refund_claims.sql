-- Tests recovery of refund claims abandoned by interrupted workers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd4030000-0000-0000-0000-000000000001'
\set eventCategoryID 'd4030000-0000-0000-0000-000000000002'
\set eventID 'd4030000-0000-0000-0000-000000000003'
\set groupCategoryID 'd4030000-0000-0000-0000-000000000017'
\set groupID 'd4030000-0000-0000-0000-000000000018'
\set pendingPurchaseID 'd4030000-0000-0000-0000-000000000004'
\set pendingRefundID 'd4030000-0000-0000-0000-000000000005'
\set recentClaimID 'd4030000-0000-0000-0000-000000000006'
\set recentPurchaseID 'd4030000-0000-0000-0000-000000000007'
\set recentRefundID 'd4030000-0000-0000-0000-000000000008'
\set staleClaimID 'd4030000-0000-0000-0000-000000000009'
\set staleFailedClaimID 'd4030000-0000-0000-0000-000000000019'
\set staleFailedPurchaseID 'd4030000-0000-0000-0000-000000000020'
\set staleFailedRefundID 'd4030000-0000-0000-0000-000000000021'
\set stalePurchaseID 'd4030000-0000-0000-0000-000000000010'
\set staleRefundID 'd4030000-0000-0000-0000-000000000011'
\set staleSucceededClaimID 'd4030000-0000-0000-0000-000000000012'
\set staleSucceededPurchaseID 'd4030000-0000-0000-0000-000000000013'
\set staleSucceededRefundID 'd4030000-0000-0000-0000-000000000014'
\set ticketTypeID 'd4030000-0000-0000-0000-000000000015'
\set userID 'd4030000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the stale claim fixtures
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.test/mobile.png',
    'https://example.test/banner.png',
    :'communityID',
    'Community',
    'Community',
    'https://example.test/logo.png',
    'stale-refund-community'
);

-- Event category used by the stale claim event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the stale claim group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the stale claim event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- User owning all stale claim purchases
insert into "user" (auth_hash, email, user_id, username)
values ('user', 'user@example.test', :'userID', 'user');

-- Event owning all stale claim purchases
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values (
    'Event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Event',
    'USD',
    'event',
    'UTC'
);

-- Ticket type referenced by all stale claim purchases
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values (:'eventID', :'ticketTypeID', 1, 100, 'General admission');

-- Purchases backing recent, stale, succeeded, and non-processing refunds
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    payment_provider_id,
    provider_payment_reference,

    charge_model,
    connected_seller_id,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_total_minor,
    seller_snapshot,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
) values
    (2500, 'USD', :'eventID', :'pendingPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_pending', 'direct-charge', 'acct_refunds', 0, 'ch_stale_pending', 'cs_stale_pending', 'acct_refunds', 2500, '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb, 2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb),
    (2500, 'USD', :'eventID', :'recentPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_recent', 'direct-charge', 'acct_refunds', 0, 'ch_stale_recent', 'cs_stale_recent', 'acct_refunds', 2500, '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb, 2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb),
    (2500, 'USD', :'eventID', :'staleFailedPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_stale_failed', 'direct-charge', 'acct_refunds', 0, 'ch_stale_failed', 'cs_stale_failed', 'acct_refunds', 2500, '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb, 2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb),
    (2500, 'USD', :'eventID', :'stalePurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_stale', 'direct-charge', 'acct_refunds', 0, 'ch_stale', 'cs_stale', 'acct_refunds', 2500, '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb, 2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb),
    (2500, 'USD', :'eventID', :'staleSucceededPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_stale_succeeded', 'direct-charge', 'acct_refunds', 0, 'ch_stale_succeeded', 'cs_stale_succeeded', 'acct_refunds', 2500, '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb, 2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb);

-- Refund rows covering prior failure, stale outcomes, recent, and non-processing states
insert into event_purchase_refund (
    amount_minor,
    attempt_count,
    claim_id,
    claimed_at,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,

    failure_message,
    provider_refund_id,
    provider_refunded_at
) values
    (2500, 0, null, null, 'USD', :'pendingPurchaseID', :'pendingRefundID', 'refund-pending', 'event-cancellation', 'stripe', 'provider-pending', null, null, null),
    (2500, 1, :'recentClaimID', current_timestamp - interval '14 minutes', 'USD', :'recentPurchaseID', :'recentRefundID', 'refund-recent', 'event-cancellation', 'stripe', 'processing', null, null, null),
    (2500, 2, :'staleFailedClaimID', current_timestamp - interval '16 minutes', 'USD', :'staleFailedPurchaseID', :'staleFailedRefundID', 'refund-stale-failed', 'event-cancellation', 'stripe', 'processing', 'provider unavailable', null, null),
    (2500, 1, :'staleClaimID', current_timestamp - interval '16 minutes', 'USD', :'stalePurchaseID', :'staleRefundID', 'refund-stale', 'event-cancellation', 'stripe', 'processing', null, null, null),
    (2500, 1, :'staleSucceededClaimID', current_timestamp - interval '16 minutes', 'USD', :'staleSucceededPurchaseID', :'staleSucceededRefundID', 'refund-stale-succeeded', 'event-cancellation', 'stripe', 'processing', null, 're_stale_succeeded', current_timestamp);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release every claim older than the processing timeout
select is(
    requeue_stale_event_purchase_refund_claims(),
    3,
    'Should release every claim older than the processing timeout'
);

-- Should leave recent and non-processing refunds unchanged
select results_eq(
    format($$
        select event_purchase_refund_id, claim_id, status
        from event_purchase_refund
        where event_purchase_refund_id in (%L::uuid, %L::uuid)
        order by event_purchase_refund_id
    $$, :'pendingRefundID', :'recentRefundID'),
    format($$ values
        (%L::uuid, null::uuid, 'provider-pending'::text),
        (%L::uuid, %L::uuid, 'processing'::text)
    $$, :'pendingRefundID', :'recentRefundID', :'recentClaimID'),
    'Should leave recent and non-processing refunds unchanged'
);

-- Should preserve an existing provider failure for reconciliation
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message, status
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'staleFailedRefundID'),
    $$ values (null::uuid, null::timestamptz, 'provider unavailable'::text, 'provider-failed'::text) $$,
    'Should preserve an existing provider failure for reconciliation'
);

-- Should preserve a recorded provider success for local finalization
select results_eq(
    format($$
        select
            claim_id,
            claimed_at,
            failure_message,
            next_attempt_at = current_timestamp,
            provider_refund_id,
            status
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'staleSucceededRefundID'),
    $$ values (null::uuid, null::timestamptz, null::text, true, 're_stale_succeeded'::text, 'provider-succeeded'::text) $$,
    'Should preserve a recorded provider success for local finalization'
);

-- Should requeue a stale unknown outcome as retryable failure
select results_eq(
    format($$
        select
            claim_id,
            claimed_at,
            failure_message,
            next_attempt_at = current_timestamp,
            status,
            terminal_failure
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'staleRefundID'),
    $$ values (null::uuid, null::timestamptz, 'refund worker claim expired'::text, true, 'provider-failed'::text, false) $$,
    'Should requeue a stale unknown outcome as retryable failure'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
