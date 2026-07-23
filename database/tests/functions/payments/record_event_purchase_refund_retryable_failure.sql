-- Tests releasing retryable refund claims with bounded provider backoff.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set blankClaimID 'd4020000-0000-0000-0000-000000000001'
\set blankPurchaseID 'd4020000-0000-0000-0000-000000000002'
\set blankRefundID 'd4020000-0000-0000-0000-000000000003'
\set cappedClaimID 'd4020000-0000-0000-0000-000000000004'
\set cappedPurchaseID 'd4020000-0000-0000-0000-000000000005'
\set cappedRefundID 'd4020000-0000-0000-0000-000000000006'
\set communityID 'd4020000-0000-0000-0000-000000000007'
\set eventCategoryID 'd4020000-0000-0000-0000-000000000008'
\set eventID 'd4020000-0000-0000-0000-000000000009'
\set groupCategoryID 'd4020000-0000-0000-0000-000000000010'
\set groupID 'd4020000-0000-0000-0000-000000000011'
\set normalClaimID 'd4020000-0000-0000-0000-000000000012'
\set normalPurchaseID 'd4020000-0000-0000-0000-000000000013'
\set normalRefundID 'd4020000-0000-0000-0000-000000000014'
\set pendingPurchaseID 'd4020000-0000-0000-0000-000000000015'
\set pendingRefundID 'd4020000-0000-0000-0000-000000000016'
\set ticketTypeID 'd4020000-0000-0000-0000-000000000017'
\set userID 'd4020000-0000-0000-0000-000000000018'
\set wrongClaimID 'd4020000-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the retryable refund fixtures
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
    'retryable-refund-community'
);

-- Event category used by the retryable refund event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the retryable refund group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the retryable refund event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- User owning all retryable refund purchases
insert into "user" (auth_hash, email, user_id, username)
values ('user', 'user@example.test', :'userID', 'user');

-- Event owning all retryable refund purchases
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

-- Ticket type referenced by all retryable refund purchases
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values (:'eventID', :'ticketTypeID', 1, 100, 'General admission');

-- Purchases backing normal, blank-message, capped, and invalid-state refunds
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
    (2500, 'USD', :'eventID', :'blankPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_blank'),
    (2500, 'USD', :'eventID', :'cappedPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_capped'),
    (2500, 'USD', :'eventID', :'normalPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_normal'),
    (2500, 'USD', :'eventID', :'pendingPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_pending');

-- Refund rows covering message normalization, backoff bounds, and invalid state
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
    status
) values
    (2500, 2, :'blankClaimID', current_timestamp, 'USD', :'blankPurchaseID', :'blankRefundID', 'refund-blank', 'event-cancellation', 'stripe', 'processing'),
    (2500, 10, :'cappedClaimID', current_timestamp, 'USD', :'cappedPurchaseID', :'cappedRefundID', 'refund-capped', 'event-cancellation', 'stripe', 'processing'),
    (2500, 1, :'normalClaimID', current_timestamp, 'USD', :'normalPurchaseID', :'normalRefundID', 'refund-normal', 'event-cancellation', 'stripe', 'processing'),
    (2500, 1, null, null, 'USD', :'pendingPurchaseID', :'pendingRefundID', 'refund-pending', 'event-cancellation', 'stripe', 'provider-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should normalize and persist a retryable provider failure
select lives_ok(
    format(
        $$select record_event_purchase_refund_retryable_failure(%L::uuid, %L::uuid, '  provider unavailable  ')$$,
        :'normalRefundID', :'normalClaimID'
    ),
    'Should normalize and persist a retryable provider failure'
);

-- Should release the claim and schedule first-attempt backoff
select results_eq(
    format($$
        select
            claim_id,
            claimed_at,
            failure_message,
            next_attempt_at = current_timestamp + interval '1 minute',
            status,
            terminal_failure
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'normalRefundID'),
    $$ values (null::uuid, null::timestamptz, 'provider unavailable'::text, true, 'provider-failed'::text, false) $$,
    'Should release the claim and schedule first-attempt backoff'
);

-- Should replace a blank failure message with the durable default
select lives_ok(
    format(
        $$select record_event_purchase_refund_retryable_failure(%L::uuid, %L::uuid, '   ')$$,
        :'blankRefundID', :'blankClaimID'
    ),
    'Should accept a blank retryable failure message'
);
select results_eq(
    format($$
        select failure_message, next_attempt_at = current_timestamp + interval '2 minutes'
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'blankRefundID'),
    $$ values ('provider refund attempt failed'::text, true) $$,
    'Should replace a blank failure message with the durable default'
);

-- Should cap exponential backoff at thirty minutes
select lives_ok(
    format(
        $$select record_event_purchase_refund_retryable_failure(%L::uuid, %L::uuid, 'provider unavailable')$$,
        :'cappedRefundID', :'cappedClaimID'
    ),
    'Should accept a retryable failure at the backoff cap'
);
select results_eq(
    format($$
        select next_attempt_at = current_timestamp + interval '30 minutes'
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'cappedRefundID'),
    $$ values (true) $$,
    'Should cap exponential backoff at thirty minutes'
);

-- Should reject a stale worker claim
select throws_ok(
    format(
        $$select record_event_purchase_refund_retryable_failure(%L::uuid, %L::uuid, 'failure')$$,
        :'normalRefundID', :'wrongClaimID'
    ),
    'event purchase refund claim is no longer current',
    'Should reject a stale worker claim'
);

-- Should reject a refund outside processing state
select throws_ok(
    format(
        $$select record_event_purchase_refund_retryable_failure(%L::uuid, %L::uuid, 'failure')$$,
        :'pendingRefundID', :'wrongClaimID'
    ),
    'event purchase refund claim is no longer current',
    'Should reject a refund outside processing state'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
