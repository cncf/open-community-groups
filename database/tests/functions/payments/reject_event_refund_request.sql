-- Tests rejecting pending attendee refund requests.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '79460000-0000-0000-0000-000000000001'
\set communityID '79460000-0000-0000-0000-000000000002'
\set eventCategoryID '79460000-0000-0000-0000-000000000003'
\set eventID '79460000-0000-0000-0000-000000000004'
\set eventTicketTypeID '79460000-0000-0000-0000-000000000005'
\set groupCategoryID '79460000-0000-0000-0000-000000000006'
\set groupID '79460000-0000-0000-0000-000000000007'
\set missingGroupID '79460000-0000-0000-0000-000000000013'
\set missingPurchaseID '79460000-0000-0000-0000-000000000008'
\set priceWindowID '79460000-0000-0000-0000-000000000009'
\set purchaseID '79460000-0000-0000-0000-000000000010'
\set refundRequestID '79460000-0000-0000-0000-000000000011'
\set userID '79460000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'actorUserID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- Ticket type and price window
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Price window that supplies the purchase amount
select fx_event_ticket_price_window(:'priceWindowID', :'eventTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Purchase and refund request
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
    :'purchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-requested',
    'General admission',
    :'userID',
    'direct-charge', 'acct_refunds', 0, 'stripe', 'ch_reject', 'cs_reject',
    'acct_refunds', 'pi_reject', 2500,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500, 0, 'inclusive', 'manual', 'professional-event-admission', '{}'::jsonb
);

-- Pending refund request rejected by the test scenarios
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'refundRequestID',
    :'purchaseID',
    :'userID',
    'pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a null rejection reason before mutating refund state
select throws_ok(
    format($$select reject_event_refund_request(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null
    )$$, :'actorUserID', :'groupID', :'purchaseID'),
    'OCG01',
    'refund rejection reason is required',
    'Should reject a null rejection reason before mutating refund state'
);

-- Should reject a whitespace-only rejection reason before mutating refund state
select throws_ok(
    format($$select reject_event_refund_request(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        '   '
    )$$, :'actorUserID', :'groupID', :'purchaseID'),
    'OCG01',
    'refund rejection reason is required',
    'Should reject a whitespace-only rejection reason before mutating refund state'
);

-- Should leave refund state and audit history unchanged after invalid input
select results_eq(
    format($$
        select
            (select status from event_purchase where event_purchase_id = %L::uuid),
            (select review_note from event_refund_request where event_refund_request_id = %L::uuid),
            (select reviewed_at from event_refund_request where event_refund_request_id = %L::uuid),
            (select reviewed_by_user_id from event_refund_request where event_refund_request_id = %L::uuid),
            (select status from event_refund_request where event_refund_request_id = %L::uuid),
            (select count(*) from audit_log)
    $$, :'purchaseID', :'refundRequestID', :'refundRequestID', :'refundRequestID', :'refundRequestID'),
    $$ values ('refund-requested'::text, null::text, null::timestamptz, null::uuid, 'pending'::text, 0::bigint) $$,
    'Should leave refund state and audit history unchanged after invalid input'
);

-- Should reject a request outside the requested group
select throws_ok(
    format($$select reject_event_refund_request(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'Not eligible'
    )$$, :'actorUserID', :'missingGroupID', :'purchaseID'),
    'OCG01',
    'refund request not found',
    'Should reject a request outside the requested group'
);

-- Should reject a pending refund request
select is(
    reject_event_refund_request(
        :'actorUserID'::uuid,
        :'groupID'::uuid,
        :'purchaseID'::uuid,
        '  Not eligible  '
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'user_id', :'userID'::uuid
    ),
    'Should reject a pending refund request'
);

-- Should persist the updated purchase and refund request fields
select results_eq(
    format($$
        select
            (select status from event_purchase where event_purchase_id = %L::uuid),
            (select review_note from event_refund_request where event_refund_request_id = %L::uuid),
            (select reviewed_at is not null from event_refund_request where event_refund_request_id = %L::uuid),
            (select reviewed_by_user_id from event_refund_request where event_refund_request_id = %L::uuid),
            (select status from event_refund_request where event_refund_request_id = %L::uuid)
    $$, :'purchaseID', :'refundRequestID', :'refundRequestID', :'refundRequestID', :'refundRequestID'),
    format(
        $$ values ('completed'::text, 'Not eligible'::text, true, %L::uuid, 'rejected'::text) $$,
        :'actorUserID'
    ),
    'Should persist the updated purchase and refund request fields'
);

-- Should create the expected rejection audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            community_id,
            event_id,
            group_id,
            details->>'event_purchase_id',
            details->>'user_id'
        from audit_log
    $$,
    format($$ values (
        'event_refund_rejected'::text,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L,
        %L
    ) $$, :'actorUserID', :'communityID', :'eventID', :'groupID', :'purchaseID', :'userID'),
    'Should create the expected rejection audit row'
);

-- Should reject missing pending refund requests
select throws_ok(
    format($$select reject_event_refund_request(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'Not eligible'
    )$$, :'actorUserID', :'groupID', :'missingPurchaseID'),
    'OCG01',
    'refund request not found',
    'Should reject missing pending refund requests'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
