-- Tests payment job constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set buyerID 'c0e20000-0000-0000-0000-000000000001'
\set claimID 'c0e20000-0000-0000-0000-000000000002'
\set communityID 'c0e20000-0000-0000-0000-000000000003'
\set completingJobID 'c0e20000-0000-0000-0000-000000000004'
\set completingPurchaseID 'c0e20000-0000-0000-0000-000000000005'
\set completingRefundID 'c0e20000-0000-0000-0000-000000000006'
\set eventCategoryID 'c0e20000-0000-0000-0000-000000000007'
\set eventID 'c0e20000-0000-0000-0000-000000000008'
\set groupCategoryID 'c0e20000-0000-0000-0000-000000000009'
\set groupID 'c0e20000-0000-0000-0000-00000000000a'
\set operatorID 'c0e20000-0000-0000-0000-00000000000b'
\set recoveringJobID 'c0e20000-0000-0000-0000-00000000000c'
\set recoveringPurchaseID 'c0e20000-0000-0000-0000-00000000000d'
\set recoveringRefundID 'c0e20000-0000-0000-0000-00000000000e'
\set ticketTypeID 'c0e20000-0000-0000-0000-00000000000f'
\set workPurchaseID 'c0e20000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Buyer of the refunded purchases
select fx_user(:'buyerID');

-- Operator completing the external refund recovery
select fx_user(:'operatorID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event selling the refunded tickets
select fx_event(:'eventID', :'groupID', :'eventCategoryID', '{"payment_currency_code": "USD"}');

-- Ticket type of the refunded purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', '{"title": "General admission"}');

-- Paid direct-charge purchases owning the payment jobs
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    connected_seller_id,
    currency_code,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
select
    purchase.event_purchase_id::uuid,
    2500,
    'direct-charge',
    :'eventID',
    :'ticketTypeID',
    purchase.status,
    'General admission',
    :'buyerID',

    'acct_c0e20000',
    'USD',
    0,
    'stripe',
    'ch_' || purchase.event_purchase_id,
    'cs_' || purchase.event_purchase_id,
    'acct_c0e20000',
    'pi_' || purchase.event_purchase_id,
    2500,
    '{"connected_account_id": "acct_c0e20000", "display_name": "Payment Job Seller", "provider": "stripe"}'::jsonb,
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (values
    (:'completingPurchaseID', 'refund-pending'),
    (:'recoveringPurchaseID', 'refund-recovery-pending'),
    (:'workPurchaseID', 'refund-pending')
) as purchase (event_purchase_id, status);

-- Pending refund job whose refund is already finalized
insert into payment_job (
    payment_job_id,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status
) values (
    :'completingJobID',
    :'completingPurchaseID',
    'c0e20000-completing',
    'event-purchase-refund',
    'stripe',
    'pending'
);

-- Failed refund job awaiting external recovery
insert into payment_job (
    payment_job_id,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,

    failure_message
) values (
    :'recoveringJobID',
    :'recoveringPurchaseID',
    'c0e20000-recovering',
    'event-purchase-refund',
    'stripe',
    'failed',

    'destination account is closed'
);

-- Finalized refund of the completing job
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status,

    finalized_at,
    provider_refund_id
) values (
    :'completingRefundID',
    2500,
    'USD',
    :'completingPurchaseID',
    'event-cancellation',
    :'completingJobID',
    'stripe',
    'finalized',

    current_timestamp,
    're_c0e20000_completing'
);

-- Terminally failed refund finalized by the external recovery
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
    :'recoveringRefundID',
    2500,
    'USD',
    :'recoveringPurchaseID',
    'event-cancellation',
    :'recoveringJobID',
    'stripe',
    'provider-failed',
    true,

    current_timestamp,
    're_c0e20000_recovering'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept claimed processing jobs
select lives_ok(
    format(
        $$
            insert into payment_job (
                event_purchase_id,
                idempotency_key,
                kind,
                payment_provider_id,
                status,

                claim_id,
                claimed_at
            ) values (
                %L::uuid,
                'c0e20000-claimed',
                'event-purchase-refund',
                'stripe',
                'processing',

                %L::uuid,
                current_timestamp
            )
        $$,
        :'workPurchaseID',
        :'claimID'
    ),
    'Should accept claimed processing jobs'
);

-- Should accept completed jobs with a completion time
select lives_ok(
    format(
        $$
            update payment_job
            set
                completed_at = current_timestamp,
                status = 'completed'
            where payment_job_id = %L::uuid
        $$,
        :'completingJobID'
    ),
    'Should accept completed jobs with a completion time'
);

-- Should accept completed jobs with full recovery evidence
select lives_ok(
    format(
        $$
            update payment_job
            set
                completed_at = current_timestamp,
                recovery_completed_at = current_timestamp,
                recovery_completed_by_user_id = %L::uuid,
                recovery_note = 'Verified by finance',
                recovery_reference = 'bank-transfer-123',
                status = 'completed'
            where payment_job_id = %L::uuid
        $$,
        :'operatorID',
        :'recoveringJobID'
    ),
    'Should accept completed jobs with full recovery evidence'
);

-- Should reject completed jobs without a completion time
select throws_ok(
    format(
        $$
            insert into payment_job (
                event_purchase_id,
                idempotency_key,
                kind,
                payment_provider_id,
                status
            ) values (
                %L::uuid,
                'c0e20000-completed-untimed',
                'event-purchase-refund',
                'stripe',
                'completed'
            )
        $$,
        :'workPurchaseID'
    ),
    '23514',
    'new row for relation "payment_job" violates check constraint "payment_job_completed_chk"',
    'Should reject completed jobs without a completion time'
);

-- Should reject partial recovery evidence
select throws_ok(
    format(
        $$
            insert into payment_job (
                event_purchase_id,
                idempotency_key,
                kind,
                payment_provider_id,
                status,

                recovery_reference
            ) values (
                %L::uuid,
                'c0e20000-partial-recovery',
                'event-purchase-refund',
                'stripe',
                'pending',

                'bank-transfer-456'
            )
        $$,
        :'workPurchaseID'
    ),
    '23514',
    'new row for relation "payment_job" violates check constraint "payment_job_recovery_chk"',
    'Should reject partial recovery evidence'
);

-- Should reject processing jobs without a claim
select throws_ok(
    format(
        $$
            insert into payment_job (
                event_purchase_id,
                idempotency_key,
                kind,
                payment_provider_id,
                status,

                claimed_at
            ) values (
                %L::uuid,
                'c0e20000-unclaimed',
                'event-purchase-refund',
                'stripe',
                'processing',

                current_timestamp
            )
        $$,
        :'workPurchaseID'
    ),
    '23514',
    'new row for relation "payment_job" violates check constraint "payment_job_claim_chk"',
    'Should reject processing jobs without a claim'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
