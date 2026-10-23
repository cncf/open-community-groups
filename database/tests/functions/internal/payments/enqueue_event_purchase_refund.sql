-- Tests enqueueing provider refund work for event purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'e7a50000-0000-0000-0000-000000000001'
\set communityID 'e7a50000-0000-0000-0000-000000000002'
\set eventCategoryID 'e7a50000-0000-0000-0000-000000000003'
\set eventID 'e7a50000-0000-0000-0000-000000000004'
\set existingJobID 'e7a50000-0000-0000-0000-000000000005'
\set existingPurchaseID 'e7a50000-0000-0000-0000-000000000006'
\set existingRefundID 'e7a50000-0000-0000-0000-000000000007'
\set existingUserID 'e7a50000-0000-0000-0000-000000000008'
\set groupCategoryID 'e7a50000-0000-0000-0000-000000000009'
\set groupID 'e7a50000-0000-0000-0000-000000000010'
\set linkedPurchaseID 'e7a50000-0000-0000-0000-000000000011'
\set linkedRefundRequestID 'e7a50000-0000-0000-0000-000000000012'
\set linkedUserID 'e7a50000-0000-0000-0000-000000000013'
\set ticketTypeID 'e7a50000-0000-0000-0000-000000000014'
\set unlinkedPurchaseID 'e7a50000-0000-0000-0000-000000000015'
\set unlinkedUserID 'e7a50000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the event
select fx_community(:'communityID');

-- Organizer who initiates the linked refund
select fx_user(:'actorID');

-- Attendee whose purchase already has refund work
select fx_user(:'existingUserID');

-- Attendee whose refund links a request, an actor and a review note
select fx_user(:'linkedUserID');

-- Attendee whose refund has no optional links
select fx_user(:'unlinkedUserID');

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

-- Direct-charge purchases for the existing, linked and unlinked refund scenarios
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
    2500, 'direct-charge', 'acct_e7a5', 'USD', :'eventID', :'existingPurchaseID',
    :'ticketTypeID', 0, 'stripe', 'ch_e7a50000_existing',
    'cs_e7a50000_existing', 'acct_e7a5', 'pi_e7a50000_existing', 2500, 0,
    '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 2500, 0,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'existingUserID', '{}'::jsonb
), (
    2500, 'direct-charge', 'acct_e7a5', 'USD', :'eventID', :'linkedPurchaseID',
    :'ticketTypeID', 0, 'stripe', 'ch_e7a50000_linked',
    'cs_e7a50000_linked', 'acct_e7a5', 'pi_e7a50000_linked', 2500, 0,
    '{"display_name":"Sponsor"}'::jsonb, 'refund-requested', 2500, 0,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'linkedUserID', '{}'::jsonb
), (
    1800, 'direct-charge', 'acct_e7a5', 'USD', :'eventID', :'unlinkedPurchaseID',
    :'ticketTypeID', 0, 'stripe', 'ch_e7a50000_unlinked',
    'cs_e7a50000_unlinked', 'acct_e7a5', 'pi_e7a50000_unlinked', 1800, 0,
    '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 1800, 0,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'unlinkedUserID', '{}'::jsonb
);

-- Approving attendee request linked to the queued refund
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'linkedRefundRequestID',
    :'linkedPurchaseID',
    :'linkedUserID',
    'approving'
);

-- Refund job that already owns the purchase-level idempotency key
insert into payment_job (
    payment_job_id,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id
) values (
    :'existingJobID',
    :'existingPurchaseID',
    'event-purchase-refund-' || :'existingPurchaseID',
    'event-purchase-refund',
    'stripe'
);

-- Refund already queued for the existing purchase
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
    :'existingRefundID',
    2500,
    'USD',
    :'existingPurchaseID',
    'automatic-unfulfillable-checkout',
    :'existingJobID',
    'stripe',
    'provider-pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Queue a linked refund for an amount that differs from the stored provider total
select enqueue_event_purchase_refund(
    (select ep from event_purchase ep where ep.event_purchase_id = :'linkedPurchaseID'),
    'refund-request-approval',
    2000,
    :'linkedRefundRequestID',
    :'actorID',
    'Approved by organizer'
) as "linkedRefundID" \gset

-- Should queue a linked refund for a purchase without refund work
select results_eq(
    format($$
        select
            epr.amount_minor,
            epr.currency_code,
            epr.event_purchase_id,
            epr.event_refund_request_id,
            epr.initiated_by_user_id,
            epr.kind,
            epr.payment_provider_id,
            epr.review_note,
            epr.status,
            pj.event_purchase_id,
            pj.idempotency_key,
            pj.kind,
            pj.payment_provider_id,
            pj.status
        from event_purchase_refund epr
        join payment_job pj on pj.payment_job_id = epr.payment_job_id
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'linkedRefundID'),
    format($$ values (
        2000::bigint,
        'USD'::text,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'refund-request-approval'::text,
        'stripe'::text,
        'Approved by organizer'::text,
        'provider-pending'::text,
        %L::uuid,
        %L::text,
        'event-purchase-refund'::text,
        'stripe'::text,
        'pending'::text
    ) $$,
        :'linkedPurchaseID',
        :'linkedRefundRequestID',
        :'actorID',
        :'linkedPurchaseID',
        'event-purchase-refund-' || :'linkedPurchaseID'
    ),
    'Should queue a linked refund for a purchase without refund work'
);

-- Queue a refund relying on the optional parameter defaults
select enqueue_event_purchase_refund(
    (select ep from event_purchase ep where ep.event_purchase_id = :'unlinkedPurchaseID'),
    'automatic-unfulfillable-checkout',
    1800
) as "unlinkedRefundID" \gset

-- Should queue a refund without optional links
select results_eq(
    format($$
        select
            epr.amount_minor,
            epr.event_purchase_id,
            epr.event_refund_request_id,
            epr.initiated_by_user_id,
            epr.kind,
            epr.review_note,
            epr.status,
            pj.idempotency_key
        from event_purchase_refund epr
        join payment_job pj on pj.payment_job_id = epr.payment_job_id
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'unlinkedRefundID'),
    format($$ values (
        1800::bigint,
        %L::uuid,
        null::uuid,
        null::uuid,
        'automatic-unfulfillable-checkout'::text,
        null::text,
        'provider-pending'::text,
        %L::text
    ) $$,
        :'unlinkedPurchaseID',
        'event-purchase-refund-' || :'unlinkedPurchaseID'
    ),
    'Should queue a refund without optional links'
);

-- Should return null when refund work already exists for the purchase
select is(
    enqueue_event_purchase_refund(
        (select ep from event_purchase ep where ep.event_purchase_id = :'existingPurchaseID'),
        'event-cancellation',
        2500,
        null,
        :'actorID'
    ),
    null::uuid,
    'Should return null when refund work already exists for the purchase'
);

-- Should keep only the existing refund work when its idempotency key already exists
select results_eq(
    format($$
        select
            (select count(*)::int from event_purchase_refund where event_purchase_id = %L::uuid),
            (select count(*)::int from payment_job where event_purchase_id = %L::uuid),
            (select kind from event_purchase_refund where event_purchase_id = %L::uuid)
    $$, :'existingPurchaseID', :'existingPurchaseID', :'existingPurchaseID'),
    $$ values (1, 1, 'automatic-unfulfillable-checkout'::text) $$,
    'Should keep only the existing refund work when its idempotency key already exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
