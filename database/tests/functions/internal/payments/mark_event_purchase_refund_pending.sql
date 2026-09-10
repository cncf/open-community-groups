-- Tests marking event purchases refund-pending.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set confirmedAttendeePurchaseID 'f3100000-0000-0000-0000-000000000001'
\set confirmedAttendeeUserID 'f3100000-0000-0000-0000-000000000002'
\set communityID 'f3100000-0000-0000-0000-000000000003'
\set eventCategoryID 'f3100000-0000-0000-0000-000000000004'
\set eventID 'f3100000-0000-0000-0000-000000000005'
\set expiredDiscountCodeID 'f3100000-0000-0000-0000-000000000006'
\set expiredDiscountPurchaseID 'f3100000-0000-0000-0000-000000000007'
\set expiredDiscountUserID 'f3100000-0000-0000-0000-000000000008'
\set groupCategoryID 'f3100000-0000-0000-0000-000000000009'
\set groupID 'f3100000-0000-0000-0000-00000000000a'
\set pendingDiscountCodeID 'f3100000-0000-0000-0000-00000000000b'
\set pendingDiscountPurchaseID 'f3100000-0000-0000-0000-00000000000c'
\set pendingDiscountUserID 'f3100000-0000-0000-0000-00000000000d'
\set ticketTypeID 'f3100000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'confirmedAttendeeUserID');
select fx_user(:'expiredDiscountUserID');
select fx_user(:'pendingDiscountUserID');

-- Group with direct-charge payment recipient
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_mark_event_purchase_refund_pending'
    )
));

-- Event hosting purchases that are moved to refund-pending
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Ticket type used by refund-pending purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Refund pending admission'
));

-- Discount codes reserved by pending and expired purchases
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values
    (
        :'expiredDiscountCodeID',
        500,
        4,
        true,
        'MARK_EVENT_PURCHASE_REFUND_PENDING_EXPIRED',
        :'eventID',
        'fixed_amount',
        'Expired Refund Pending Discount'
    ),
    (
        :'pendingDiscountCodeID',
        500,
        0,
        true,
        'MARK_EVENT_PURCHASE_REFUND_PENDING_PENDING',
        :'eventID',
        'fixed_amount',
        'Pending Refund Pending Discount'
    );

-- Purchases with provider amounts already recorded for refund-pending transition
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    final_platform_fee_amount_minor,
    hold_expires_at,
    payment_provider_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
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
) values
    (
        2500,
        'direct-charge',
        'acct_mark_event_purchase_refund_pending',
        'USD',
        0,
        null,
        null,
        :'eventID',
        :'confirmedAttendeePurchaseID',
        :'ticketTypeID',
        62,
        current_timestamp + interval '1 hour',
        'stripe',
        250,
        62,
        'mark-event-purchase-refund-pending-charge-confirmed',
        'mark-event-purchase-refund-pending-session-confirmed',
        'acct_mark_event_purchase_refund_pending',
        2500,
        '{"connected_account_id":"acct_mark_event_purchase_refund_pending","display_name":"Refund Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        2500,
        0,
        'inclusive',
        'manual',
        'professional-event-admission',
        'Confirmed attendee admission',
        :'confirmedAttendeeUserID',
        '{}'::jsonb
    ),
    (
        2000,
        'direct-charge',
        'acct_mark_event_purchase_refund_pending',
        'USD',
        500,
        'MARK_EVENT_PURCHASE_REFUND_PENDING_EXPIRED',
        :'expiredDiscountCodeID',
        :'eventID',
        :'expiredDiscountPurchaseID',
        :'ticketTypeID',
        50,
        current_timestamp - interval '1 hour',
        'stripe',
        250,
        50,
        'mark-event-purchase-refund-pending-charge-expired',
        'mark-event-purchase-refund-pending-session-expired',
        'acct_mark_event_purchase_refund_pending',
        2000,
        '{"connected_account_id":"acct_mark_event_purchase_refund_pending","display_name":"Refund Sponsor","provider":"stripe"}'::jsonb,
        'expired',
        2000,
        0,
        'inclusive',
        'manual',
        'professional-event-admission',
        'Expired discount admission',
        :'expiredDiscountUserID',
        '{}'::jsonb
    ),
    (
        2000,
        'direct-charge',
        'acct_mark_event_purchase_refund_pending',
        'USD',
        500,
        'MARK_EVENT_PURCHASE_REFUND_PENDING_PENDING',
        :'pendingDiscountCodeID',
        :'eventID',
        :'pendingDiscountPurchaseID',
        :'ticketTypeID',
        50,
        current_timestamp + interval '1 hour',
        'stripe',
        250,
        50,
        'mark-event-purchase-refund-pending-charge-pending',
        'mark-event-purchase-refund-pending-session-pending',
        'acct_mark_event_purchase_refund_pending',
        2000,
        '{"connected_account_id":"acct_mark_event_purchase_refund_pending","display_name":"Refund Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        2000,
        0,
        'inclusive',
        'manual',
        'professional-event-admission',
        'Pending discount admission',
        :'pendingDiscountUserID',
        '{}'::jsonb
    );

-- Checkout-created attendee hold for the pending discounted purchase
insert into event_attendee (
    event_id,
    manually_invited,
    registration_answers,
    status,
    user_id
) values (
    :'eventID',
    false,
    '{"answers": [{"question_id": "f3100000-0000-0000-0000-00000000000f", "value": "Pending refund"}]}'::jsonb,
    'registration-questions-pending',
    :'pendingDiscountUserID'
);

-- Confirmed attendee row that refund-pending cleanup must keep
insert into event_attendee (
    event_id,
    manually_invited,
    status,
    user_id
) values (
    :'eventID',
    false,
    'confirmed',
    :'confirmedAttendeeUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Move each purchase through the refund-pending helper before assertions
select mark_event_purchase_refund_pending(
    (select ep from event_purchase ep where ep.event_purchase_id = :'confirmedAttendeePurchaseID'),
    'mark-event-purchase-refund-pending-reference-confirmed'
);
select mark_event_purchase_refund_pending(
    (select ep from event_purchase ep where ep.event_purchase_id = :'expiredDiscountPurchaseID'),
    'mark-event-purchase-refund-pending-reference-expired'
);
select mark_event_purchase_refund_pending(
    (select ep from event_purchase ep where ep.event_purchase_id = :'pendingDiscountPurchaseID'),
    'mark-event-purchase-refund-pending-reference-pending'
);

-- Should keep confirmed attendee rows
select results_eq(
    format(
        $$
            select status, manually_invited
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'confirmedAttendeeUserID'
    ),
    $$ values ('confirmed'::text, false) $$,
    'Should keep confirmed attendee rows'
);

-- Should mark pending purchases refund-pending
select results_eq(
    format(
        $$
            select
                hold_expires_at is null,
                provider_payment_reference,
                status
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'pendingDiscountPurchaseID'
    ),
    $$ values (
        true,
        'mark-event-purchase-refund-pending-reference-pending'::text,
        'refund-pending'::text
    ) $$,
    'Should mark pending purchases refund-pending'
);

-- Should preserve expired discount availability
select is(
    (
        select available
        from event_discount_code
        where event_discount_code_id = :'expiredDiscountCodeID'
    ),
    4,
    'Should preserve expired discount availability'
);

-- Should release checkout attendee hold rows
select is(
    (
        select count(*)::int
        from event_attendee
        where event_id = :'eventID'
        and user_id = :'pendingDiscountUserID'
    ),
    0,
    'Should release checkout attendee hold rows'
);

-- Should restore pending discount availability
select is(
    (
        select available
        from event_discount_code
        where event_discount_code_id = :'pendingDiscountCodeID'
    ),
    1,
    'Should restore pending discount availability'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
