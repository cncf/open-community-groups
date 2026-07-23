-- Tests administrator requeueing of exhausted transient refund failures.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd4040000-0000-0000-0000-000000000001'
\set eventCategoryID 'd4040000-0000-0000-0000-000000000002'
\set eventID 'd4040000-0000-0000-0000-000000000003'
\set failedPurchaseID 'd4040000-0000-0000-0000-000000000004'
\set failedRefundID 'd4040000-0000-0000-0000-000000000005'
\set failedUserID 'd4040000-0000-0000-0000-000000000021'
\set groupCategoryID 'd4040000-0000-0000-0000-000000000006'
\set groupID 'd4040000-0000-0000-0000-000000000007'
\set missingGroupID 'd4040000-0000-0000-0000-000000000009'
\set missingPurchaseID 'd4040000-0000-0000-0000-000000000010'
\set pendingPurchaseID 'd4040000-0000-0000-0000-000000000011'
\set pendingRefundID 'd4040000-0000-0000-0000-000000000012'
\set pendingUserID 'd4040000-0000-0000-0000-000000000022'
\set scopePurchaseID 'd4040000-0000-0000-0000-000000000013'
\set scopeRefundID 'd4040000-0000-0000-0000-000000000014'
\set scopeUserID 'd4040000-0000-0000-0000-000000000023'
\set terminalPurchaseID 'd4040000-0000-0000-0000-000000000015'
\set terminalRefundID 'd4040000-0000-0000-0000-000000000016'
\set terminalUserID 'd4040000-0000-0000-0000-000000000024'
\set ticketTypeID 'd4040000-0000-0000-0000-000000000017'
\set underBudgetPurchaseID 'd4040000-0000-0000-0000-000000000018'
\set underBudgetRefundID 'd4040000-0000-0000-0000-000000000019'
\set underBudgetUserID 'd4040000-0000-0000-0000-000000000025'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the administrator retry fixtures
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
    'requeue-refund-community'
);

-- Event category used by the administrator retry event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the administrator retry group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the administrator retry event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Users isolating every administrator retry scenario
insert into "user" (auth_hash, email, user_id, username) values
    ('failed', 'failed@example.test', :'failedUserID', 'failed'),
    ('pending', 'pending@example.test', :'pendingUserID', 'pending'),
    ('scope', 'scope@example.test', :'scopeUserID', 'scope'),
    ('terminal', 'terminal@example.test', :'terminalUserID', 'terminal'),
    ('under-budget', 'under-budget@example.test', :'underBudgetUserID', 'under-budget');

-- Event owning every administrator retry purchase
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

-- Ticket type referenced by every administrator retry purchase
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values (:'eventID', :'ticketTypeID', 1, 100, 'General admission');

-- Purchases backing retryable, terminal, under-budget, and scope fixtures
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
    (2500, 'USD', :'eventID', :'failedPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'failedUserID', 'stripe', 'pi_failed'),
    (2500, 'USD', :'eventID', :'pendingPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'pendingUserID', 'stripe', 'pi_pending'),
    (2500, 'USD', :'eventID', :'scopePurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'scopeUserID', 'stripe', 'pi_scope'),
    (2500, 'USD', :'eventID', :'terminalPurchaseID', :'ticketTypeID', 'refund-recovery-pending', 'General admission', :'terminalUserID', 'stripe', 'pi_terminal'),
    (2500, 'USD', :'eventID', :'underBudgetPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'underBudgetUserID', 'stripe', 'pi_under_budget');

-- Refund rows covering both retryable statuses and every rejection guard
insert into event_purchase_refund (
    amount_minor,
    attempt_count,
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
    provider_refund_id
) values
    (2500, 10, 'USD', :'failedPurchaseID', :'failedRefundID', 'refund-failed', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-failed', false, 'provider unavailable', null),
    (2500, 10, 'USD', :'pendingPurchaseID', :'pendingRefundID', 'refund-pending', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-pending', false, 'provider unavailable', null),
    (2500, 10, 'USD', :'scopePurchaseID', :'scopeRefundID', 'refund-scope', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-failed', false, 'provider unavailable', null),
    (2500, 10, 'USD', :'terminalPurchaseID', :'terminalRefundID', 'refund-terminal', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-failed', true, 'terminal', 're_terminal'),
    (2500, 9, 'USD', :'underBudgetPurchaseID', :'underBudgetRefundID', 'refund-under-budget', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-failed', false, 'provider unavailable', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should requeue an exhausted provider failure
select lives_ok(
    format(
        'select requeue_event_purchase_refund(%L::uuid, %L::uuid)',
        :'groupID', :'failedPurchaseID'
    ),
    'Should requeue an exhausted provider failure'
);

-- Should reset the retry budget and clear failure state
select results_eq(
    format($$
        select attempt_count, failure_message, next_attempt_at = current_timestamp, status
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'failedRefundID'),
    $$ values (0, null::text, true, 'provider-pending'::text) $$,
    'Should reset the retry budget and clear failure state'
);

-- Should requeue an exhausted pending refund
select lives_ok(
    format(
        'select requeue_event_purchase_refund(%L::uuid, %L::uuid)',
        :'groupID', :'pendingPurchaseID'
    ),
    'Should requeue an exhausted pending refund'
);

-- Should reset an exhausted pending refund to immediate work
select results_eq(
    format($$
        select attempt_count, failure_message, next_attempt_at = current_timestamp, status
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'pendingRefundID'),
    $$ values (0, null::text, true, 'provider-pending'::text) $$,
    'Should reset an exhausted pending refund to immediate work'
);

-- Should reject a terminal provider failure
select throws_ok(
    format(
        'select requeue_event_purchase_refund(%L::uuid, %L::uuid)',
        :'groupID', :'terminalPurchaseID'
    ),
    'retryable event purchase refund not found',
    'Should reject a terminal provider failure'
);

-- Should reject a refund before its retry budget is exhausted
select throws_ok(
    format(
        'select requeue_event_purchase_refund(%L::uuid, %L::uuid)',
        :'groupID', :'underBudgetPurchaseID'
    ),
    'retryable event purchase refund not found',
    'Should reject a refund before its retry budget is exhausted'
);

-- Should reject a refund outside the requested group
select throws_ok(
    format(
        'select requeue_event_purchase_refund(%L::uuid, %L::uuid)',
        :'missingGroupID', :'scopePurchaseID'
    ),
    'retryable event purchase refund not found',
    'Should reject a refund outside the requested group'
);

-- Should reject a missing purchase refund
select throws_ok(
    format(
        'select requeue_event_purchase_refund(%L::uuid, %L::uuid)',
        :'groupID', :'missingPurchaseID'
    ),
    'retryable event purchase refund not found',
    'Should reject a missing purchase refund'
);

-- Should preserve every rejected refund state
select results_eq(
    format($$
        select event_purchase_refund_id, attempt_count, status, terminal_failure
        from event_purchase_refund
        where event_purchase_refund_id in (%L::uuid, %L::uuid, %L::uuid)
        order by event_purchase_refund_id
    $$, :'scopeRefundID', :'terminalRefundID', :'underBudgetRefundID'),
    format($$ values
        (%L::uuid, 10, 'provider-failed'::text, false),
        (%L::uuid, 10, 'provider-failed'::text, true),
        (%L::uuid, 9, 'provider-failed'::text, false)
    $$, :'scopeRefundID', :'terminalRefundID', :'underBudgetRefundID'),
    'Should preserve every rejected refund state'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
