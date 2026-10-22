-- Tests retrieving event purchase refunds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79010000-0000-0000-0000-000000000001'
\set claimedClaimID '79010000-0000-0000-0000-000000000011'
\set claimedJobID '79010000-0000-0000-0000-000000000014'
\set claimedPurchaseID '79010000-0000-0000-0000-000000000012'
\set claimedRefundID '79010000-0000-0000-0000-000000000013'
\set eventCategoryID '79010000-0000-0000-0000-000000000002'
\set eventID '79010000-0000-0000-0000-000000000003'
\set groupCategoryID '79010000-0000-0000-0000-000000000004'
\set groupID '79010000-0000-0000-0000-000000000005'
\set missingPurchaseID '79010000-0000-0000-0000-000000000010'
\set ticketTypeID '79010000-0000-0000-0000-000000000006'
\set userID '79010000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Ticketed event containing the claimed refund purchase
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '1 day'
));

-- Ticket type purchased before the refund
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Purchase currently owned by a refund worker claim
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
) values (
    2500,
    'USD',
    :'eventID',
    :'claimedPurchaseID',
    :'ticketTypeID',
    'refund-pending',
    'General admission',
    :'userID',

    'stripe',
    'pi_claimed_123',
    'direct-charge', 'acct_refunds', 0, 'ch_get_claimed', 'cs_get_claimed',
    'acct_refunds', 2500,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
);

-- Processing payment job currently claimed for provider processing
insert into payment_job (
    payment_job_id, attempt_count, event_purchase_id, idempotency_key,
    kind, payment_provider_id, status,

    claim_id, claimed_at
) values (
    :'claimedJobID', 2, :'claimedPurchaseID',
    'event-purchase-refund-claimed-get-event-purchase-refund',
    'event-purchase-refund', 'stripe', 'processing',

    :'claimedClaimID', current_timestamp
);

-- Durable refund currently claimed for provider processing
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status
) values (
    2500,
    'USD',
    :'claimedPurchaseID',
    :'claimedRefundID',
    'event-cancellation',
    :'claimedJobID',
    'stripe',
    'provider-pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should load an active worker claim
select is(
    get_event_purchase_refund(:'claimedPurchaseID'::uuid),
    jsonb_build_object(
        'amount_minor', 2500,
        'attempt_count', 2,
        'claim_id', :'claimedClaimID'::uuid,
        'currency_code', 'USD',
        'event_purchase_id', :'claimedPurchaseID'::uuid,
        'event_purchase_refund_id', :'claimedRefundID'::uuid,
        'idempotency_key', 'event-purchase-refund-claimed-get-event-purchase-refund',
        'kind', 'event-cancellation',
        'payment_job_id', :'claimedJobID'::uuid,
        'payment_provider', 'stripe',
        'status', 'provider-pending',
        'terminal_failure', false
    ),
    'Should load an active worker claim'
);

-- Should reject a purchase without a durable refund
select throws_ok(
    format(
        $$select get_event_purchase_refund(%L::uuid)$$,
        :'missingPurchaseID'
    ),
    'P0001',
    'event purchase refund not found',
    'Should reject a purchase without a durable refund'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
