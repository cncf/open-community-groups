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

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'failedUserID');
select fx_user(:'pendingUserID');
select fx_user(:'scopeUserID');
select fx_user(:'terminalUserID');
select fx_user(:'underBudgetUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning every administrator retry purchase
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('payment_currency_code', 'USD'));

-- Ticket type referenced by every administrator retry purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General admission'
));

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
    (2500, 'USD', :'eventID', :'failedPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'failedUserID', 'stripe', 'pi_failed', 'direct-charge', 'acct_refunds', 0, 'ch_requeue_failed', 'cs_requeue_failed', 'acct_refunds', 2500, '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb, 2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb),
    (2500, 'USD', :'eventID', :'pendingPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'pendingUserID', 'stripe', 'pi_pending_refund_requeue', 'direct-charge', 'acct_refunds', 0, 'ch_requeue_pending', 'cs_requeue_pending', 'acct_refunds', 2500, '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb, 2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb),
    (2500, 'USD', :'eventID', :'scopePurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'scopeUserID', 'stripe', 'pi_scope', 'direct-charge', 'acct_refunds', 0, 'ch_requeue_scope', 'cs_requeue_scope', 'acct_refunds', 2500, '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb, 2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb),
    (2500, 'USD', :'eventID', :'terminalPurchaseID', :'ticketTypeID', 'refund-recovery-pending', 'General admission', :'terminalUserID', 'stripe', 'pi_terminal', 'direct-charge', 'acct_refunds', 0, 'ch_requeue_terminal', 'cs_requeue_terminal', 'acct_refunds', 2500, '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb, 2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb),
    (2500, 'USD', :'eventID', :'underBudgetPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'underBudgetUserID', 'stripe', 'pi_under_budget', 'direct-charge', 'acct_refunds', 0, 'ch_requeue_under', 'cs_requeue_under', 'acct_refunds', 2500, '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb, 2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb);

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
    (2500, 10, 'USD', :'failedPurchaseID', :'failedRefundID', 'refund-failed-refund-requeue', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-failed', false, 'provider unavailable', null),
    (2500, 10, 'USD', :'pendingPurchaseID', :'pendingRefundID', 'refund-pending-refund-requeue', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-pending', false, 'provider unavailable', null),
    (2500, 10, 'USD', :'scopePurchaseID', :'scopeRefundID', 'refund-scope', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-failed', false, 'provider unavailable', null),
    (2500, 10, 'USD', :'terminalPurchaseID', :'terminalRefundID', 'refund-terminal-refund-requeue', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-failed', true, 'terminal', 're_terminal_refund_requeue'),
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
    'OCG01',
    'retryable event purchase refund not found',
    'Should reject a terminal provider failure'
);

-- Should reject a refund before its retry budget is exhausted
select throws_ok(
    format(
        'select requeue_event_purchase_refund(%L::uuid, %L::uuid)',
        :'groupID', :'underBudgetPurchaseID'
    ),
    'OCG01',
    'retryable event purchase refund not found',
    'Should reject a refund before its retry budget is exhausted'
);

-- Should reject a refund outside the requested group
select throws_ok(
    format(
        'select requeue_event_purchase_refund(%L::uuid, %L::uuid)',
        :'missingGroupID', :'scopePurchaseID'
    ),
    'OCG01',
    'retryable event purchase refund not found',
    'Should reject a refund outside the requested group'
);

-- Should reject a missing purchase refund
select throws_ok(
    format(
        'select requeue_event_purchase_refund(%L::uuid, %L::uuid)',
        :'groupID', :'missingPurchaseID'
    ),
    'OCG01',
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
