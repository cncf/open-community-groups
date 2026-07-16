-- Tests claiming provider refund work with retry and terminal-state guards.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd4010000-0000-0000-0000-000000000001'
\set eventCategoryID 'd4010000-0000-0000-0000-000000000002'
\set eventID 'd4010000-0000-0000-0000-000000000003'
\set exhaustedPurchaseID 'd4010000-0000-0000-0000-000000000004'
\set exhaustedRefundID 'd4010000-0000-0000-0000-000000000005'
\set failedPurchaseID 'd4010000-0000-0000-0000-000000000006'
\set failedRefundID 'd4010000-0000-0000-0000-000000000007'
\set futurePurchaseID 'd4010000-0000-0000-0000-000000000008'
\set futureRefundID 'd4010000-0000-0000-0000-000000000009'
\set groupCategoryID 'd4010000-0000-0000-0000-000000000010'
\set groupID 'd4010000-0000-0000-0000-000000000011'
\set otherProviderPurchaseID 'd4010000-0000-0000-0000-000000000012'
\set otherProviderRefundID 'd4010000-0000-0000-0000-000000000013'
\set pendingPurchaseID 'd4010000-0000-0000-0000-000000000014'
\set pendingRefundID 'd4010000-0000-0000-0000-000000000015'
\set succeededPurchaseID 'd4010000-0000-0000-0000-000000000016'
\set succeededRefundID 'd4010000-0000-0000-0000-000000000017'
\set terminalPurchaseID 'd4010000-0000-0000-0000-000000000018'
\set terminalRefundID 'd4010000-0000-0000-0000-000000000019'
\set ticketTypeID 'd4010000-0000-0000-0000-000000000020'
\set userID 'd4010000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Additional provider used to verify provider-scoped claims
insert into payment_provider (display_name, payment_provider_id)
values ('Other Provider', 'other-provider');

-- Community owning the refund queue fixtures
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
    'claim-refund-community'
);

-- Event category used by the refund queue event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the refund queue group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the refund queue event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- User owning all independent purchase fixtures
insert into "user" (auth_hash, email, user_id, username)
values ('user', 'user@example.test', :'userID', 'user');

-- Event owning all independent purchase fixtures
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

-- Ticket type referenced by all independent purchases
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values (:'eventID', :'ticketTypeID', 1, 100, 'General admission');

-- Purchases backing due, excluded, and provider-complete refund rows
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
    (2500, 'USD', :'eventID', :'exhaustedPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_exhausted'),
    (2500, 'USD', :'eventID', :'failedPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_failed'),
    (2500, 'USD', :'eventID', :'futurePurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_future'),
    (2500, 'USD', :'eventID', :'otherProviderPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'other-provider', 'pi_other'),
    (2500, 'USD', :'eventID', :'pendingPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_pending'),
    (2500, 'USD', :'eventID', :'succeededPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'userID', 'stripe', 'pi_succeeded'),
    (2500, 'USD', :'eventID', :'terminalPurchaseID', :'ticketTypeID', 'refund-recovery-pending', 'General admission', :'userID', 'stripe', 'pi_terminal');

-- Refund rows covering priority, retry, scheduling, exhaustion, and provider scoping
insert into event_purchase_refund (
    amount_minor,
    attempt_count,
    created_at,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_provider_id,
    status,
    terminal_failure,

    failure_message,
    provider_refund_id,
    provider_refunded_at
) values
    (2500, 10, '2024-01-04 00:00:00+00', 'USD', :'exhaustedPurchaseID', :'exhaustedRefundID', 'refund-exhausted', 'event-cancellation', '2024-01-04 00:00:00+00', 'stripe', 'provider-pending', false, null, null, null),
    (2500, 3, '2024-01-02 00:00:00+00', 'USD', :'failedPurchaseID', :'failedRefundID', 'refund-failed', 'event-cancellation', '2024-01-02 00:00:00+00', 'stripe', 'provider-failed', false, 'provider unavailable', null, null),
    (2500, 0, '2024-01-05 00:00:00+00', 'USD', :'futurePurchaseID', :'futureRefundID', 'refund-future', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-pending', false, null, null, null),
    (2500, 0, '2024-01-01 00:00:00+00', 'USD', :'otherProviderPurchaseID', :'otherProviderRefundID', 'refund-other', 'event-cancellation', '2024-01-01 00:00:00+00', 'other-provider', 'provider-pending', false, null, null, null),
    (2500, 0, '2024-01-01 00:00:00+00', 'USD', :'pendingPurchaseID', :'pendingRefundID', 'refund-pending', 'event-cancellation', '2024-01-01 00:00:00+00', 'stripe', 'provider-pending', false, null, null, null),
    (2500, 4, '2024-01-03 00:00:00+00', 'USD', :'succeededPurchaseID', :'succeededRefundID', 'refund-succeeded', 'event-cancellation', '2024-01-03 00:00:00+00', 'stripe', 'provider-succeeded', false, null, 're_succeeded', current_timestamp),
    (2500, 1, '2024-01-06 00:00:00+00', 'USD', :'terminalPurchaseID', :'terminalRefundID', 'refund-terminal', 'event-cancellation', '2024-01-06 00:00:00+00', 'stripe', 'provider-failed', true, 'terminal', 're_terminal', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should claim provider-complete work before provider reconciliation work
select results_eq(
    $$
        select
            result->>'community_id',
            result->>'event_id',
            result->>'event_purchase_refund_id',
            (result->>'attempt_count')::int,
            result->>'provider_payment_reference',
            result->>'provider_refund_id',
            result->>'status'
        from (select claim_event_purchase_refund('stripe')::jsonb as result) claimed
    $$,
    format($$ values (
        %L::text,
        %L::text,
        %L::text,
        4,
        'pi_succeeded'::text,
        're_succeeded'::text,
        'processing'::text
    ) $$, :'communityID', :'eventID', :'succeededRefundID'),
    'Should claim provider-complete work with its notification context'
);

-- Should persist a claim without incrementing provider-complete attempts
select results_eq(
    format($$
        select attempt_count, claim_id is not null, claimed_at is not null, status
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'succeededRefundID'),
    $$ values (4, true, true, 'processing'::text) $$,
    'Should persist a claim without incrementing provider-complete attempts'
);

-- Should claim due pending work and increment its attempt count
select results_eq(
    $$
        select
            result->>'event_purchase_refund_id',
            (result->>'attempt_count')::int,
            result->>'status'
        from (select claim_event_purchase_refund('stripe')::jsonb as result) claimed
    $$,
    format($$ values (%L::text, 1, 'processing'::text) $$, :'pendingRefundID'),
    'Should claim due pending work and increment its attempt count'
);

-- Should claim due retryable failure work and increment its attempt count
select results_eq(
    $$
        select
            result->>'event_purchase_refund_id',
            (result->>'attempt_count')::int,
            result->>'status'
        from (select claim_event_purchase_refund('stripe')::jsonb as result) claimed
    $$,
    format($$ values (%L::text, 4, 'processing'::text) $$, :'failedRefundID'),
    'Should claim due retryable failure work and increment its attempt count'
);

-- Should return no work after every eligible refund is claimed
select is(
    claim_event_purchase_refund('stripe')::jsonb,
    null::jsonb,
    'Should return no work after every eligible refund is claimed'
);

-- Should leave future, exhausted, terminal, and other-provider work unclaimed
select results_eq(
    format($$
        select event_purchase_refund_id, claim_id, status
        from event_purchase_refund
        where event_purchase_refund_id in (%L::uuid, %L::uuid, %L::uuid, %L::uuid)
        order by event_purchase_refund_id
    $$, :'exhaustedRefundID', :'futureRefundID', :'otherProviderRefundID', :'terminalRefundID'),
    format($$ values
        (%L::uuid, null::uuid, 'provider-pending'::text),
        (%L::uuid, null::uuid, 'provider-pending'::text),
        (%L::uuid, null::uuid, 'provider-pending'::text),
        (%L::uuid, null::uuid, 'provider-failed'::text)
    $$, :'exhaustedRefundID', :'futureRefundID', :'otherProviderRefundID', :'terminalRefundID'),
    'Should leave future, exhausted, terminal, and other-provider work unclaimed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
