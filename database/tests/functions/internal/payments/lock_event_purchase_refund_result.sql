-- Tests validating and locking the rows a provider refund result updates.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set claimID 'f24a0000-0000-0000-0000-000000000001'
\set claimedJobID 'f24a0000-0000-0000-0000-000000000002'
\set claimedPurchaseID 'f24a0000-0000-0000-0000-000000000003'
\set claimedRefundID 'f24a0000-0000-0000-0000-000000000004'
\set communityID 'f24a0000-0000-0000-0000-000000000005'
\set eventCategoryID 'f24a0000-0000-0000-0000-000000000006'
\set eventID 'f24a0000-0000-0000-0000-000000000007'
\set eventTicketTypeID 'f24a0000-0000-0000-0000-000000000008'
\set groupCategoryID 'f24a0000-0000-0000-0000-000000000009'
\set groupID 'f24a0000-0000-0000-0000-000000000010'
\set missingRefundID 'f24a0000-0000-0000-0000-000000000011'
\set otherClaimID 'f24a0000-0000-0000-0000-000000000012'
\set unclaimedJobID 'f24a0000-0000-0000-0000-000000000013'
\set unclaimedPurchaseID 'f24a0000-0000-0000-0000-000000000014'
\set unclaimedRefundID 'f24a0000-0000-0000-0000-000000000015'
\set userID 'f24a0000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns the event
select fx_community(:'communityID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Buyer of the refunded purchases
select fx_user(:'userID');

-- Group that owns the event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose purchases are being refunded
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Ticket type snapshotted by the purchases
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID');

-- Purchases whose refunds are claimed and unclaimed by a worker
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
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
) values (
    :'claimedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'userID',
    'direct-charge', 'acct_lock_refund_result', 0, 'stripe', 'ch_lock_refund_result_claimed',
    'cs_lock_refund_result_claimed', 'acct_lock_refund_result', 'pi_lock_refund_result_claimed', 2500,
    '{"connected_account_id":"acct_lock_refund_result","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
), (
    :'unclaimedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'userID',
    'direct-charge', 'acct_lock_refund_result', 0, 'stripe', 'ch_lock_refund_result_unclaimed',
    'cs_lock_refund_result_unclaimed', 'acct_lock_refund_result', 'pi_lock_refund_result_unclaimed', 2500,
    '{"connected_account_id":"acct_lock_refund_result","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
);

-- Refund payment jobs claimed and unclaimed by a worker
insert into payment_job (
    payment_job_id, attempt_count, event_purchase_id, idempotency_key,
    kind, payment_provider_id, status,

    claim_id, claimed_at
) values (
    :'claimedJobID', 1, :'claimedPurchaseID',
    'lock-refund-result-' || :'claimedPurchaseID',
    'event-purchase-refund', 'stripe', 'processing',

    :'claimID', current_timestamp
), (
    :'unclaimedJobID', 0, :'unclaimedPurchaseID',
    'lock-refund-result-' || :'unclaimedPurchaseID',
    'event-purchase-refund', 'stripe', 'pending',

    null, null
);

-- Provider refunds owned by the claimed and unclaimed jobs
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status
) values (
    :'claimedRefundID',
    2500,
    'USD',
    :'claimedPurchaseID',
    'event-cancellation',
    :'claimedJobID',
    'stripe',
    'provider-pending'
), (
    :'unclaimedRefundID',
    2500,
    'USD',
    :'unclaimedPurchaseID',
    'event-cancellation',
    :'unclaimedJobID',
    'stripe',
    'provider-pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an unclaimed job when no claim is expected
-- Take the locks outside a pgTAP subtransaction so the next scenario can read the refund row xmax
select (job_row).payment_job_id as "unclaimedLockedJobID"
from lock_event_purchase_refund_result(
    :'unclaimedRefundID',
    'lock-refund-result-' || :'unclaimedPurchaseID',
    're_lock_unclaimed',
    null
) \gset

select is(
    :'unclaimedLockedJobID'::uuid,
    :'unclaimedJobID'::uuid,
    'Should accept an unclaimed job when no claim is expected'
);

-- Should acquire the refund row lock for the provider result
-- Seed foreign key checks already set the event, purchase and job xmax, so only the refund row can show it
select is(
    (
        select xmax::text
        from event_purchase_refund
        where event_purchase_refund_id = :'unclaimedRefundID'::uuid
    ),
    (pg_current_xact_id()::text::bigint % 4294967296)::text,
    'Should acquire the refund row lock for the provider result'
);

-- Should check the idempotency key before the provider refund id
select throws_ok(
    format($$select * from lock_event_purchase_refund_result(%L::uuid, '', '', null)$$, :'claimedRefundID'),
    'P0001',
    'expected idempotency key is required',
    'Should check the idempotency key before the provider refund id'
);

-- Should reject a blank expected idempotency key
select throws_ok(
    format($$select * from lock_event_purchase_refund_result(%L::uuid, '   ', 're_lock_claimed', null)$$, :'claimedRefundID'),
    'P0001',
    'expected idempotency key is required',
    'Should reject a blank expected idempotency key'
);

-- Should reject a blank provider refund id
select throws_ok(
    format(
        $$select * from lock_event_purchase_refund_result(%L::uuid, %L, '   ', null)$$,
        :'claimedRefundID',
        'lock-refund-result-' || :'claimedPurchaseID'
    ),
    'P0001',
    'provider refund id is required',
    'Should reject a blank provider refund id'
);

-- Should reject a claimed result when the job is no longer claimed
select throws_ok(
    format(
        $$select * from lock_event_purchase_refund_result(%L::uuid, %L, 're_lock_unclaimed', %L::uuid)$$,
        :'unclaimedRefundID',
        'lock-refund-result-' || :'unclaimedPurchaseID',
        :'claimID'
    ),
    'P0001',
    'event purchase refund claim is stale',
    'Should reject a claimed result when the job is no longer claimed'
);

-- Should reject a null expected idempotency key
select throws_ok(
    format($$select * from lock_event_purchase_refund_result(%L::uuid, null, 're_lock_claimed', null)$$, :'claimedRefundID'),
    'P0001',
    'expected idempotency key is required',
    'Should reject a null expected idempotency key'
);

-- Should reject a null provider refund id
select throws_ok(
    format(
        $$select * from lock_event_purchase_refund_result(%L::uuid, %L, null, null)$$,
        :'claimedRefundID',
        'lock-refund-result-' || :'claimedPurchaseID'
    ),
    'P0001',
    'provider refund id is required',
    'Should reject a null provider refund id'
);

-- Should reject a result from another worker claim
select throws_ok(
    format(
        $$select * from lock_event_purchase_refund_result(%L::uuid, %L, 're_lock_claimed', %L::uuid)$$,
        :'claimedRefundID',
        'lock-refund-result-' || :'claimedPurchaseID',
        :'otherClaimID'
    ),
    'P0001',
    'event purchase refund claim is stale',
    'Should reject a result from another worker claim'
);

-- Should reject an empty expected idempotency key
select throws_ok(
    format($$select * from lock_event_purchase_refund_result(%L::uuid, '', 're_lock_claimed', null)$$, :'claimedRefundID'),
    'P0001',
    'expected idempotency key is required',
    'Should reject an empty expected idempotency key'
);

-- Should reject an empty provider refund id
select throws_ok(
    format(
        $$select * from lock_event_purchase_refund_result(%L::uuid, %L, '', null)$$,
        :'claimedRefundID',
        'lock-refund-result-' || :'claimedPurchaseID'
    ),
    'P0001',
    'provider refund id is required',
    'Should reject an empty provider refund id'
);

-- Should reject an unclaimed result when a worker claims the job
select throws_ok(
    format(
        $$select * from lock_event_purchase_refund_result(%L::uuid, %L, 're_lock_claimed', null)$$,
        :'claimedRefundID',
        'lock-refund-result-' || :'claimedPurchaseID'
    ),
    'P0001',
    'event purchase refund claim is stale',
    'Should reject an unclaimed result when a worker claims the job'
);

-- Should reject an unknown refund
select throws_ok(
    format(
        $$select * from lock_event_purchase_refund_result(%L::uuid, 'lock-refund-result-missing', 're_lock_missing', %L::uuid)$$,
        :'missingRefundID',
        :'claimID'
    ),
    'P0001',
    'event purchase refund not found',
    'Should reject an unknown refund'
);

-- Should return the locked job and refund rows for the current claim
select results_eq(
    format($$
        select
            (job_row).claim_id,
            (job_row).payment_job_id,
            (refund_row).event_purchase_refund_id,
            (refund_row).status
        from lock_event_purchase_refund_result(%L::uuid, %L, 're_lock_claimed', %L::uuid)
    $$,
        :'claimedRefundID',
        'lock-refund-result-' || :'claimedPurchaseID',
        :'claimID'
    ),
    format(
        $$ values (%L::uuid, %L::uuid, %L::uuid, 'provider-pending'::text) $$,
        :'claimID',
        :'claimedJobID',
        :'claimedRefundID'
    ),
    'Should return the locked job and refund rows for the current claim'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
