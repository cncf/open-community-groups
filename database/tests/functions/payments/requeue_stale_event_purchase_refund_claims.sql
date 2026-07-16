-- Tests recovery of refund claims abandoned by interrupted workers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

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
    provider_payment_reference
) values
    (2500, 'USD', :'eventID', :'pendingPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_pending'),
    (2500, 'USD', :'eventID', :'recentPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_recent'),
    (2500, 'USD', :'eventID', :'stalePurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_stale'),
    (2500, 'USD', :'eventID', :'staleSucceededPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_stale_succeeded');

-- Refund rows covering stale unknown, stale succeeded, recent, and non-processing states
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

    provider_refund_id,
    provider_refunded_at
) values
    (2500, 0, null, null, 'USD', :'pendingPurchaseID', :'pendingRefundID', 'refund-pending', 'event-cancellation', 'stripe', 'provider-pending', null, null),
    (2500, 1, :'recentClaimID', current_timestamp - interval '14 minutes', 'USD', :'recentPurchaseID', :'recentRefundID', 'refund-recent', 'event-cancellation', 'stripe', 'processing', null, null),
    (2500, 1, :'staleClaimID', current_timestamp - interval '16 minutes', 'USD', :'stalePurchaseID', :'staleRefundID', 'refund-stale', 'event-cancellation', 'stripe', 'processing', null, null),
    (2500, 1, :'staleSucceededClaimID', current_timestamp - interval '16 minutes', 'USD', :'staleSucceededPurchaseID', :'staleSucceededRefundID', 'refund-stale-succeeded', 'event-cancellation', 'stripe', 'processing', 're_stale_succeeded', current_timestamp);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release every claim older than the processing timeout
select is(
    requeue_stale_event_purchase_refund_claims(),
    2,
    'Should release every claim older than the processing timeout'
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
