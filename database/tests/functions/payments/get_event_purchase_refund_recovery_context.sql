-- Tests loading authoritative event context for refund recovery.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79540000-0000-0000-0000-000000000001'
\set eventCategoryID '79540000-0000-0000-0000-000000000002'
\set eventID '79540000-0000-0000-0000-000000000003'
\set finalizedJobID '79540000-0000-0000-0000-000000000014'
\set finalizedPurchaseID '79540000-0000-0000-0000-000000000004'
\set finalizedRefundID '79540000-0000-0000-0000-000000000005'
\set groupCategoryID '79540000-0000-0000-0000-000000000006'
\set groupID '79540000-0000-0000-0000-000000000007'
\set missingPurchaseID '79540000-0000-0000-0000-000000000008'
\set otherGroupID '79540000-0000-0000-0000-000000000009'
\set pendingJobID '79540000-0000-0000-0000-000000000015'
\set pendingPurchaseID '79540000-0000-0000-0000-000000000010'
\set pendingRefundID '79540000-0000-0000-0000-000000000011'
\set ticketTypeID '79540000-0000-0000-0000-000000000012'
\set userID '79540000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event containing both recovery purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '1 day'
));

-- Ticket type purchased before both refunds
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Purchases before and after local refund finalization
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    payment_provider_id,
    provider_payment_reference,
    refunded_at,

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
) values (
    :'finalizedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'ticketTypeID',
    'refund-recovery-pending',
    'General admission',
    :'userID',

    'stripe',
    'pi_refund_recovery_context_finalized',
    '2024-02-01 10:00:00+00',
    'direct-charge', 'acct_refunds', 0, 'ch_context_finalized',
    'cs_context_finalized', 'acct_refunds', 2500,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
), (
    :'pendingPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'ticketTypeID',
    'refund-pending',
    'General admission',
    :'userID',

    'stripe',
    'pi_refund_recovery_context_pending',
    null,
    'direct-charge', 'acct_refunds', 0, 'ch_context_pending',
    'cs_context_pending', 'acct_refunds', 2500,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
);

-- Failed payment jobs before and after local finalization
insert into payment_job (
    payment_job_id, event_purchase_id, failure_message, idempotency_key,
    kind, payment_provider_id, status
) values (
    :'finalizedJobID',
    :'finalizedPurchaseID',
    'provider refund failed',
    'event-purchase-refund-recovery-context-finalized-job',
    'event-purchase-refund',
    'stripe',
    'failed'
), (
    :'pendingJobID',
    :'pendingPurchaseID',
    'provider refund failed',
    'event-purchase-refund-recovery-context-pending-job',
    'event-purchase-refund',
    'stripe',
    'failed'
);

-- Provider failures before and after local finalization
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status,
    terminal_failure,

    finalized_at,
    provider_refund_id
) values (
    :'finalizedRefundID',
    2500,
    'USD',
    :'finalizedPurchaseID',
    'automatic-unfulfillable-checkout',
    :'finalizedJobID',
    'stripe',
    'provider-failed',
    true,

    '2024-02-01 10:00:00+00',
    're_refund_recovery_context_finalized'
), (
    :'pendingRefundID',
    2500,
    'USD',
    :'pendingPurchaseID',
    'event-cancellation',
    :'pendingJobID',
    'stripe',
    'provider-failed',
    true,

    null,
    're_refund_recovery_context_pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a missing purchase
select throws_ok(
    format(
        $$select get_event_purchase_refund_recovery_context(%L::uuid, %L::uuid)$$,
        :'groupID',
        :'missingPurchaseID'
    ),
    'OCG01',
    'event purchase refund not found',
    'Should reject a missing purchase'
);

-- Should reject a purchase outside the requested group
select throws_ok(
    format(
        $$select get_event_purchase_refund_recovery_context(%L::uuid, %L::uuid)$$,
        :'otherGroupID',
        :'pendingPurchaseID'
    ),
    'OCG01',
    'event purchase refund not found',
    'Should reject a purchase outside the requested group'
);

-- Should return context after local finalization
select is(
    get_event_purchase_refund_recovery_context(
        :'groupID'::uuid,
        :'finalizedPurchaseID'::uuid
    ),
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'event_purchase_refund_id', :'finalizedRefundID'::uuid,

        'notification_required', false
    ),
    'Should return context after local finalization'
);

-- Should return context before local finalization
select is(
    get_event_purchase_refund_recovery_context(
        :'groupID'::uuid,
        :'pendingPurchaseID'::uuid
    ),
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'event_purchase_refund_id', :'pendingRefundID'::uuid,

        'notification_required', true
    ),
    'Should return context before local finalization'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
