-- Tests refunding free and external event purchases locally.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '79320000-0000-0000-0000-000000000001'
\set communityID '79320000-0000-0000-0000-000000000002'
\set eventCategoryID '79320000-0000-0000-0000-000000000003'
\set eventDiscountCodeID '79320000-0000-0000-0000-000000000004'
\set eventID '79320000-0000-0000-0000-000000000005'
\set eventPaidTicketTypeID '79320000-0000-0000-0000-000000000006'
\set eventTicketTypeID '79320000-0000-0000-0000-000000000007'
\set externalCompletedPurchaseID '79320000-0000-0000-0000-000000000008'
\set externalCompletedUserID '79320000-0000-0000-0000-000000000009'
\set externalEventID '79320000-0000-0000-0000-000000000010'
\set externalRequestedPurchaseID '79320000-0000-0000-0000-000000000011'
\set externalRequestedRefundRequestID '79320000-0000-0000-0000-000000000012'
\set externalRequestedUserID '79320000-0000-0000-0000-000000000013'
\set externalTicketTypeID '79320000-0000-0000-0000-000000000014'
\set freePurchaseID '79320000-0000-0000-0000-000000000015'
\set freeUserID '79320000-0000-0000-0000-000000000016'
\set groupCategoryID '79320000-0000-0000-0000-000000000017'
\set groupID '79320000-0000-0000-0000-000000000018'
\set paidPurchaseID '79320000-0000-0000-0000-000000000019'
\set paidUserID '79320000-0000-0000-0000-000000000020'
\set refundedPurchaseID '79320000-0000-0000-0000-000000000021'
\set refundedUserID '79320000-0000-0000-0000-000000000022'
\set refundRequestedPurchaseID '79320000-0000-0000-0000-000000000023'
\set refundRequestedUserID '79320000-0000-0000-0000-000000000024'
\set reviewedPurchaseID '79320000-0000-0000-0000-000000000025'
\set reviewedRefundRequestID '79320000-0000-0000-0000-000000000026'
\set reviewedUserID '79320000-0000-0000-0000-000000000027'
\set reviewerID '79320000-0000-0000-0000-000000000028'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the refunded events
select fx_community(:'communityID');

-- Organizer who performs the local refunds
select fx_user(:'actorID');

-- Owner of the completed external purchase
select fx_user(:'externalCompletedUserID');

-- Owner of the external purchase with a pending refund request
select fx_user(:'externalRequestedUserID');

-- Owner of the completed free discounted purchase
select fx_user(:'freeUserID');

-- Owner of the paid direct charge outside the local refund boundary
select fx_user(:'paidUserID');

-- Owner of the already refunded free purchase
select fx_user(:'refundedUserID');

-- Owner of the refund-requested free purchase
select fx_user(:'refundRequestedUserID');

-- Owner of the external purchase whose request already has a reviewer
select fx_user(:'reviewedUserID');

-- Organizer who reviewed the approving request earlier
select fx_user(:'reviewerID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Ticketed event holding free and paid purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- External-marked event holding externally paid purchases
select fx_event(:'externalEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/refund-locally',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', now() + interval '2 days'
));

-- Limited discount code whose reserved redemption returns on refund
insert into event_discount_code (
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_discount_code_id,
    event_id,
    kind,
    title
) values (
    true,
    2500,
    0,
    true,
    'FREEPASS',
    :'eventDiscountCodeID',
    :'eventID',
    'fixed_amount',
    'Free pass'
);

-- Paid tier of the ticketed event
select fx_event_ticket_type(:'eventPaidTicketTypeID', :'eventID', jsonb_build_object(
    'order', 2,
    'seats_total', 10,
    'title', 'Paid admission'
));

-- Free tier of the ticketed event
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Tier of the external-marked event
select fx_event_ticket_type(:'externalTicketTypeID', :'externalEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'External admission'
));

-- Free purchases covering the completed, refund-requested and refunded states
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_code,
    event_discount_code_id,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    refunded_at,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    'FREEPASS',
    :'eventDiscountCodeID',
    :'eventID',
    :'freePurchaseID',
    :'eventTicketTypeID',
    null,
    'completed',
    'General admission',
    :'freeUserID'
), (
    0,
    'USD',
    null,
    null,
    :'eventID',
    :'refundedPurchaseID',
    :'eventTicketTypeID',
    '2024-01-02 10:00:00+00',
    'refunded',
    'General admission',
    :'refundedUserID'
), (
    0,
    'USD',
    null,
    null,
    :'eventID',
    :'refundRequestedPurchaseID',
    :'eventTicketTypeID',
    null,
    'refund-requested',
    'General admission',
    :'refundRequestedUserID'
);

-- Completed direct charge outside the local refund boundary
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    status,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    2500,
    'direct-charge',
    'acct_free_boundary',
    'USD',
    :'eventID',
    :'paidPurchaseID',
    :'eventPaidTicketTypeID',
    0,
    'stripe',
    'ch_free_boundary',
    'cs_free_boundary',
    'acct_free_boundary',
    'pi_free_boundary',
    2500,
    '{"connected_account_id":"acct_free_boundary","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'completed',
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'Paid admission',
    :'paidUserID',
    '{}'::jsonb
);

-- External purchases covering the completed and refund-requested states
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    '2024-01-01 10:00:00+00',
    'KRW',
    :'externalEventID',
    :'externalCompletedPurchaseID',
    :'externalTicketTypeID',
    0,
    0,
    'completed',
    'External admission',
    :'externalCompletedUserID'
), (
    5000,
    'external',
    '2024-01-01 10:00:00+00',
    'KRW',
    :'externalEventID',
    :'externalRequestedPurchaseID',
    :'externalTicketTypeID',
    0,
    0,
    'refund-requested',
    'External admission',
    :'externalRequestedUserID'
), (
    5000,
    'external',
    '2024-01-01 10:00:00+00',
    'KRW',
    :'externalEventID',
    :'reviewedPurchaseID',
    :'externalTicketTypeID',
    0,
    0,
    'refund-requested',
    'External admission',
    :'reviewedUserID'
);

-- Pending request without a review and an approving request reviewed earlier
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status,

    reviewed_at,
    reviewed_by_user_id
) values (
    :'externalRequestedPurchaseID',
    :'externalRequestedRefundRequestID',
    :'externalRequestedUserID',
    'pending',

    null,
    null
), (
    :'reviewedPurchaseID',
    :'reviewedRefundRequestID',
    :'reviewedUserID',
    'approving',

    '2024-01-03 10:00:00+00',
    :'reviewerID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should approve a pending request with the actor as reviewer
select lives_ok(
    format(
        $$select refund_event_purchase_locally(%L::uuid, %L::uuid)$$,
        :'externalRequestedPurchaseID', :'actorID'
    ),
    'Should approve a pending request with the actor as reviewer'
);

select results_eq(
    format($$
        select
            ep.refunded_at,
            ep.status,
            err.reviewed_at,
            err.reviewed_by_user_id,
            err.status
        from event_purchase ep
        join event_refund_request err using (event_purchase_id)
        where ep.event_purchase_id = %L::uuid
    $$, :'externalRequestedPurchaseID'),
    format(
        $$ values (current_timestamp, 'refunded'::text, current_timestamp, %L::uuid, 'approved'::text) $$,
        :'actorID'
    ),
    'Should approve a pending request with the actor as reviewer'
);

-- Should keep an earlier reviewer when approving an approving request
select lives_ok(
    format(
        $$select refund_event_purchase_locally(%L::uuid, %L::uuid)$$,
        :'reviewedPurchaseID', :'actorID'
    ),
    'Should keep an earlier reviewer when approving an approving request'
);

select results_eq(
    format($$
        select
            ep.status,
            err.reviewed_at,
            err.reviewed_by_user_id,
            err.status
        from event_purchase ep
        join event_refund_request err using (event_purchase_id)
        where ep.event_purchase_id = %L::uuid
    $$, :'reviewedPurchaseID'),
    format(
        $$ values ('refunded'::text, '2024-01-03 10:00:00+00'::timestamptz, %L::uuid, 'approved'::text) $$,
        :'reviewerID'
    ),
    'Should keep an earlier reviewer when approving an approving request'
);

-- Should refund a completed external purchase
select lives_ok(
    format(
        $$select refund_event_purchase_locally(%L::uuid, %L::uuid)$$,
        :'externalCompletedPurchaseID', :'actorID'
    ),
    'Should refund a completed external purchase'
);

select results_eq(
    format($$
        select refunded_at, status
        from event_purchase
        where event_purchase_id = %L::uuid
    $$, :'externalCompletedPurchaseID'),
    $$ values (current_timestamp, 'refunded'::text) $$,
    'Should refund a completed external purchase'
);

-- Should refund a completed free purchase and restore one discount redemption
select lives_ok(
    format(
        $$select refund_event_purchase_locally(%L::uuid, %L::uuid)$$,
        :'freePurchaseID', :'actorID'
    ),
    'Should refund a completed free purchase and restore one discount redemption'
);

select results_eq(
    format($$
        select
            ep.refunded_at,
            ep.status,
            edc.available
        from event_purchase ep
        join event_discount_code edc using (event_discount_code_id)
        where ep.event_purchase_id = %L::uuid
    $$, :'freePurchaseID'),
    $$ values (current_timestamp, 'refunded'::text, 1) $$,
    'Should refund a completed free purchase and restore one discount redemption'
);

-- Should refund a refund-requested free purchase
select lives_ok(
    format(
        $$select refund_event_purchase_locally(%L::uuid, %L::uuid)$$,
        :'refundRequestedPurchaseID', :'actorID'
    ),
    'Should refund a refund-requested free purchase'
);

select results_eq(
    format($$
        select refunded_at, status
        from event_purchase
        where event_purchase_id = %L::uuid
    $$, :'refundRequestedPurchaseID'),
    $$ values (current_timestamp, 'refunded'::text) $$,
    'Should refund a refund-requested free purchase'
);

-- Should reject a paid purchase that needs provider work
select throws_ok(
    format(
        $$select refund_event_purchase_locally(%L::uuid, %L::uuid)$$,
        :'paidPurchaseID', :'actorID'
    ),
    'P0001',
    'locally refundable purchase not found',
    'Should reject a paid purchase that needs provider work'
);

-- Should reject an already refunded purchase
select throws_ok(
    format(
        $$select refund_event_purchase_locally(%L::uuid, %L::uuid)$$,
        :'refundedPurchaseID', :'actorID'
    ),
    'P0001',
    'locally refundable purchase not found',
    'Should reject an already refunded purchase'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
