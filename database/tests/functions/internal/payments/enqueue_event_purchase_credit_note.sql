-- Tests enqueueing credit note work for refunded event purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e7a40000-0000-0000-0000-000000000001'
\set eventCategoryID 'e7a40000-0000-0000-0000-000000000002'
\set eventID 'e7a40000-0000-0000-0000-000000000003'
\set existingCreditNoteID 'e7a40000-0000-0000-0000-000000000004'
\set existingCreditNoteJobID 'e7a40000-0000-0000-0000-000000000005'
\set existingPurchaseID 'e7a40000-0000-0000-0000-000000000006'
\set existingRefundID 'e7a40000-0000-0000-0000-000000000007'
\set existingRefundJobID 'e7a40000-0000-0000-0000-000000000008'
\set existingUserID 'e7a40000-0000-0000-0000-000000000009'
\set groupCategoryID 'e7a40000-0000-0000-0000-000000000010'
\set groupID 'e7a40000-0000-0000-0000-000000000011'
\set purchaseID 'e7a40000-0000-0000-0000-000000000012'
\set refundID 'e7a40000-0000-0000-0000-000000000013'
\set refundJobID 'e7a40000-0000-0000-0000-000000000014'
\set ticketTypeID 'e7a40000-0000-0000-0000-000000000015'
\set userID 'e7a40000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the event
select fx_community(:'communityID');

-- Attendee whose refund already has credit note work
select fx_user(:'existingUserID');

-- Attendee whose refund still needs its credit note
select fx_user(:'userID');

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

-- Invoiced direct-charge purchases for the existing and new credit note scenarios
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_charge_id, provider_checkout_session_id,
    provider_invoice_id, provider_object_account_id,
    provider_payment_reference, provider_total_minor,
    provisional_platform_fee_amount_minor, seller_snapshot, status,
    subtotal_excluding_tax_minor, tax_amount_minor, tax_behavior,
    tax_calculation_mode, tax_classification, ticket_title, user_id,
    venue_snapshot
) values (
    2500, 'direct-charge', 'acct_e7a4', 'USD', :'eventID', :'existingPurchaseID',
    :'ticketTypeID', 0, 'stripe', 'ch_e7a40000_existing',
    'cs_e7a40000_existing', 'in_e7a40000_existing', 'acct_e7a4',
    'pi_e7a40000_existing', 2500, 0, '{"display_name":"Sponsor"}'::jsonb,
    'refund-pending', 2300, 200, 'inclusive', 'manual',
    'professional-event-admission', 'General admission', :'existingUserID',
    '{}'::jsonb
), (
    2400, 'direct-charge', 'acct_e7a4', 'USD', :'eventID', :'purchaseID',
    :'ticketTypeID', 0, 'stripe', 'ch_e7a40000_new', 'cs_e7a40000_new',
    'in_e7a40000_new', 'acct_e7a4', 'pi_e7a40000_new', 2400, 0,
    '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 2250, 150,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'userID', '{}'::jsonb
);

-- Refund jobs of both purchases and the credit note job that already owns its key
insert into payment_job (
    payment_job_id,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id
) values (
    :'existingCreditNoteJobID',
    :'existingPurchaseID',
    'event-purchase-credit-note-' || :'existingRefundID',
    'event-purchase-credit-note',
    'stripe'
), (
    :'existingRefundJobID',
    :'existingPurchaseID',
    'event-purchase-refund-' || :'existingPurchaseID',
    'event-purchase-refund',
    'stripe'
), (
    :'refundJobID',
    :'purchaseID',
    'event-purchase-refund-' || :'purchaseID',
    'event-purchase-refund',
    'stripe'
);

-- Provider-confirmed refunds documented by the credit notes
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status,

    provider_refund_id,
    provider_refunded_at
) values (
    :'existingRefundID',
    2500,
    'USD',
    :'existingPurchaseID',
    'automatic-unfulfillable-checkout',
    :'existingRefundJobID',
    'stripe',
    'provider-succeeded',

    're_e7a40000_existing',
    current_timestamp
), (
    :'refundID',
    2400,
    'USD',
    :'purchaseID',
    'automatic-unfulfillable-checkout',
    :'refundJobID',
    'stripe',
    'provider-succeeded',

    're_e7a40000_new',
    current_timestamp
);

-- Credit note already queued for the existing refund
insert into event_purchase_credit_note (
    event_purchase_credit_note_id,
    amount_minor,
    currency_code,
    event_purchase_refund_id,
    payment_job_id,
    payment_provider_id,
    provider_object_account_id,
    tax_amount_minor
) values (
    :'existingCreditNoteID',
    2500,
    'USD',
    :'existingRefundID',
    :'existingCreditNoteJobID',
    'stripe',
    'acct_e7a4',
    200
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Queue the credit note of a refund without credit note work
select enqueue_event_purchase_credit_note(
    (select ep from event_purchase ep where ep.event_purchase_id = :'purchaseID'),
    :'refundID'
) as "creditNoteID" \gset

-- Should queue a full credit note for a refund without credit note work
select results_eq(
    format($$
        select
            epcn.amount_minor,
            epcn.currency_code,
            epcn.event_purchase_refund_id,
            epcn.payment_provider_id,
            epcn.provider_object_account_id,
            epcn.tax_amount_minor,
            pj.event_purchase_id,
            pj.idempotency_key,
            pj.kind,
            pj.payment_provider_id,
            pj.status
        from event_purchase_credit_note epcn
        join payment_job pj on pj.payment_job_id = epcn.payment_job_id
        where epcn.event_purchase_credit_note_id = %L::uuid
    $$, :'creditNoteID'),
    format($$ values (
        2400::bigint,
        'USD'::text,
        %L::uuid,
        'stripe'::text,
        'acct_e7a4'::text,
        150::bigint,
        %L::uuid,
        %L::text,
        'event-purchase-credit-note'::text,
        'stripe'::text,
        'pending'::text
    ) $$,
        :'refundID',
        :'purchaseID',
        'event-purchase-credit-note-' || :'refundID'
    ),
    'Should queue a full credit note for a refund without credit note work'
);

-- Should return null when credit note work already exists for the refund
select is(
    enqueue_event_purchase_credit_note(
        (select ep from event_purchase ep where ep.event_purchase_id = :'existingPurchaseID'),
        :'existingRefundID'
    ),
    null::uuid,
    'Should return null when credit note work already exists for the refund'
);

-- Should keep only the existing credit note work when its idempotency key already exists
select results_eq(
    format($$
        select
            (select count(*)::int from event_purchase_credit_note where event_purchase_refund_id = %L::uuid),
            (select count(*)::int from payment_job where idempotency_key = %L)
    $$, :'existingRefundID', 'event-purchase-credit-note-' || :'existingRefundID'),
    $$ values (1, 1) $$,
    'Should keep only the existing credit note work when its idempotency key already exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
