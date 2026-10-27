-- Tests enqueueing application fee adjustment work for event purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e7a30000-0000-0000-0000-000000000001'
\set eventCategoryID 'e7a30000-0000-0000-0000-000000000002'
\set eventID 'e7a30000-0000-0000-0000-000000000003'
\set existingAdjustmentID 'e7a30000-0000-0000-0000-000000000004'
\set existingJobID 'e7a30000-0000-0000-0000-000000000005'
\set existingPurchaseID 'e7a30000-0000-0000-0000-000000000006'
\set existingUserID 'e7a30000-0000-0000-0000-000000000007'
\set groupCategoryID 'e7a30000-0000-0000-0000-000000000008'
\set groupID 'e7a30000-0000-0000-0000-000000000009'
\set refundFeePurchaseID 'e7a30000-0000-0000-0000-000000000010'
\set refundFeeUserID 'e7a30000-0000-0000-0000-000000000011'
\set taxFeePurchaseID 'e7a30000-0000-0000-0000-000000000012'
\set taxFeeUserID 'e7a30000-0000-0000-0000-000000000013'
\set ticketTypeID 'e7a30000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the event
select fx_community(:'communityID');

-- Attendee whose purchase already has a tax fee adjustment
select fx_user(:'existingUserID');

-- Attendee whose refunded purchase returns its platform fee
select fx_user(:'refundFeeUserID');

-- Attendee whose purchase returns the fee overcharged before tax
select fx_user(:'taxFeeUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Paid event owning the purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by the purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Direct-charge purchases for the existing, refund fee and tax fee scenarios
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_charge_id, provider_checkout_session_id,
    provider_object_account_id, provider_payment_reference,
    provider_total_minor, provisional_platform_fee_amount_minor,
    seller_snapshot, status, subtotal_excluding_tax_minor, tax_amount_minor,
    tax_behavior, tax_calculation_mode, tax_classification, ticket_title,
    user_id, venue_snapshot
) values (
    2500, 'direct-charge', 'acct_e7a3', 'USD', :'eventID', :'existingPurchaseID',
    :'ticketTypeID', 92, 'stripe', 'ch_e7a30000_existing',
    'cs_e7a30000_existing', 'acct_e7a3', 'pi_e7a30000_existing', 2500, 100,
    '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive',
    'manual', 'professional-event-admission', 'General admission',
    :'existingUserID', '{}'::jsonb
), (
    2500, 'direct-charge', 'acct_e7a3', 'USD', :'eventID', :'refundFeePurchaseID',
    :'ticketTypeID', 100, 'stripe', 'ch_e7a30000_refund',
    'cs_e7a30000_refund', 'acct_e7a3', 'pi_e7a30000_refund', 2500, 100,
    '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 2500, 0,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'refundFeeUserID', '{}'::jsonb
), (
    2500, 'direct-charge', 'acct_e7a3', 'USD', :'eventID', :'taxFeePurchaseID',
    :'ticketTypeID', 92, 'stripe', 'ch_e7a30000_tax', 'cs_e7a30000_tax',
    'acct_e7a3', 'pi_e7a30000_tax', 2500, 100,
    '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive',
    'manual', 'professional-event-admission', 'General admission',
    :'taxFeeUserID', '{}'::jsonb
);

-- Tax fee adjustment job that already owns its purchase-level idempotency key
insert into payment_job (
    payment_job_id,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id
) values (
    :'existingJobID',
    :'existingPurchaseID',
    'event-purchase-tax-fee-adjustment-' || :'existingPurchaseID',
    'event-purchase-application-fee-adjustment',
    'stripe'
);

-- Tax fee adjustment already queued for the existing purchase
insert into event_purchase_application_fee_adjustment (
    event_purchase_application_fee_adjustment_id,
    amount_minor,
    event_purchase_id,
    kind,
    payment_job_id
) values (
    :'existingAdjustmentID',
    8,
    :'existingPurchaseID',
    'tax-reconciliation',
    :'existingJobID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Queue the platform fee returned with a refunded charge
select enqueue_event_purchase_application_fee_adjustment(
    (select ep from event_purchase ep where ep.event_purchase_id = :'refundFeePurchaseID'),
    'purchase-refund',
    100
) as "refundFeeAdjustmentID" \gset

-- Should queue a purchase refund fee adjustment under its refund key
select results_eq(
    format($$
        select
            epafa.amount_minor,
            epafa.event_purchase_id,
            epafa.kind,
            pj.event_purchase_id,
            pj.idempotency_key,
            pj.kind,
            pj.payment_provider_id,
            pj.status
        from event_purchase_application_fee_adjustment epafa
        join payment_job pj on pj.payment_job_id = epafa.payment_job_id
        where epafa.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'refundFeeAdjustmentID'),
    format($$ values (
        100::bigint,
        %L::uuid,
        'purchase-refund'::text,
        %L::uuid,
        %L::text,
        'event-purchase-application-fee-adjustment'::text,
        'stripe'::text,
        'pending'::text
    ) $$,
        :'refundFeePurchaseID',
        :'refundFeePurchaseID',
        'event-purchase-refund-fee-adjustment-' || :'refundFeePurchaseID'
    ),
    'Should queue a purchase refund fee adjustment under its refund key'
);

-- Queue the platform fee overcharged before tax was known
select enqueue_event_purchase_application_fee_adjustment(
    (select ep from event_purchase ep where ep.event_purchase_id = :'taxFeePurchaseID'),
    'tax-reconciliation',
    8
) as "taxFeeAdjustmentID" \gset

-- Should queue a tax reconciliation fee adjustment under its tax key
select results_eq(
    format($$
        select
            epafa.amount_minor,
            epafa.event_purchase_id,
            epafa.kind,
            pj.event_purchase_id,
            pj.idempotency_key,
            pj.kind,
            pj.payment_provider_id,
            pj.status
        from event_purchase_application_fee_adjustment epafa
        join payment_job pj on pj.payment_job_id = epafa.payment_job_id
        where epafa.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'taxFeeAdjustmentID'),
    format($$ values (
        8::bigint,
        %L::uuid,
        'tax-reconciliation'::text,
        %L::uuid,
        %L::text,
        'event-purchase-application-fee-adjustment'::text,
        'stripe'::text,
        'pending'::text
    ) $$,
        :'taxFeePurchaseID',
        :'taxFeePurchaseID',
        'event-purchase-tax-fee-adjustment-' || :'taxFeePurchaseID'
    ),
    'Should queue a tax reconciliation fee adjustment under its tax key'
);

-- Should reject a missing adjustment kind
select throws_ok(
    format($$
        select enqueue_event_purchase_application_fee_adjustment(
            (select ep from event_purchase ep where ep.event_purchase_id = %L::uuid),
            null,
            100
        )
    $$, :'refundFeePurchaseID'),
    'P0001',
    'unsupported application fee adjustment kind',
    'Should reject a missing adjustment kind'
);

-- Should reject an unknown adjustment kind
select throws_ok(
    format($$
        select enqueue_event_purchase_application_fee_adjustment(
            (select ep from event_purchase ep where ep.event_purchase_id = %L::uuid),
            'manual-correction',
            100
        )
    $$, :'refundFeePurchaseID'),
    'P0001',
    'unsupported application fee adjustment kind',
    'Should reject an unknown adjustment kind'
);

-- Should return null when adjustment work of the kind already exists
select is(
    enqueue_event_purchase_application_fee_adjustment(
        (select ep from event_purchase ep where ep.event_purchase_id = :'existingPurchaseID'),
        'tax-reconciliation',
        8
    ),
    null::uuid,
    'Should return null when adjustment work of the kind already exists'
);

-- Should keep only the existing adjustment work when its idempotency key already exists
select results_eq(
    format($$
        select
            (
                select count(*)::int
                from event_purchase_application_fee_adjustment
                where event_purchase_id = %L::uuid
            ),
            (select count(*)::int from payment_job where event_purchase_id = %L::uuid)
    $$, :'existingPurchaseID', :'existingPurchaseID'),
    $$ values (1, 1) $$,
    'Should keep only the existing adjustment work when its idempotency key already exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
