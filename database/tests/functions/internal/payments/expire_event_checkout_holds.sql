-- Tests expiring stale event checkout holds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cappedOfferID 'f30d0000-0000-0000-0000-000000000001'
\set cappedPurchaseID 'f30d0000-0000-0000-0000-000000000002'
\set cappedUserID 'f30d0000-0000-0000-0000-000000000003'
\set communityID 'f30d0000-0000-0000-0000-000000000004'
\set directPurchaseID 'f30d0000-0000-0000-0000-000000000005'
\set directUserID 'f30d0000-0000-0000-0000-000000000006'
\set discountCodeID 'f30d0000-0000-0000-0000-000000000007'
\set discountPurchaseID 'f30d0000-0000-0000-0000-000000000008'
\set discountUserID 'f30d0000-0000-0000-0000-000000000009'
\set eventCategoryID 'f30d0000-0000-0000-0000-00000000000a'
\set eventID 'f30d0000-0000-0000-0000-00000000000b'
\set expiredExternalPurchaseID 'f30d0000-0000-0000-0000-00000000000c'
\set expiredExternalUserID 'f30d0000-0000-0000-0000-00000000000d'
\set freePurchaseID 'f30d0000-0000-0000-0000-00000000000e'
\set freeUserID 'f30d0000-0000-0000-0000-00000000000f'
\set futurePurchaseID 'f30d0000-0000-0000-0000-000000000010'
\set futureUserID 'f30d0000-0000-0000-0000-000000000011'
\set groupCategoryID 'f30d0000-0000-0000-0000-000000000012'
\set groupID 'f30d0000-0000-0000-0000-000000000013'
\set otherEventID 'f30d0000-0000-0000-0000-000000000014'
\set otherPurchaseID 'f30d0000-0000-0000-0000-000000000015'
\set otherTicketTypeID 'f30d0000-0000-0000-0000-000000000016'
\set otherUserID 'f30d0000-0000-0000-0000-000000000017'
\set pastPurchaseID 'f30d0000-0000-0000-0000-000000000018'
\set pastUserID 'f30d0000-0000-0000-0000-000000000019'
\set pendingAttendeePurchaseID 'f30d0000-0000-0000-0000-00000000001a'
\set pendingAttendeeUserID 'f30d0000-0000-0000-0000-00000000001b'
\set ticketTypeID 'f30d0000-0000-0000-0000-00000000001c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'cappedUserID');
select fx_user(:'directUserID');
select fx_user(:'discountUserID');
select fx_user(:'expiredExternalUserID');
select fx_user(:'freeUserID');
select fx_user(:'futureUserID');
select fx_user(:'otherUserID');
select fx_user(:'pastUserID');
select fx_user(:'pendingAttendeeUserID');

-- Group shown in expired external payment notifications
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Expire Event Checkout Holds Group',
    'payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_expire_event_checkout_holds'
    )
));

-- Event whose stale checkout holds are reconciled
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'external_payment_instructions', 'Pay before the hold expires',
    'external_payment_url', 'https://pay.example.test/expire-event-checkout-holds',
    'name', 'Expire Event Checkout Holds Event',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'timezone', 'Europe/Amsterdam'
));

-- Event outside the reconciliation scope
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Target event ticket type
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 20,
    'title', 'Expire checkout admission'
));

-- Other event ticket type
select fx_event_ticket_type(:'otherTicketTypeID', :'otherEventID', jsonb_build_object(
    'seats_total', 1,
    'title', 'Other checkout admission'
));

-- Checkout-pending offer whose deadline already elapsed
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'cappedOfferID',
    2500,
    current_timestamp - interval '2 hours',
    'USD',
    0,
    :'eventID',
    :'ticketTypeID',
    current_timestamp - interval '1 hour',
    'waitlist',
    'checkout_pending',
    'Expire checkout admission',
    :'cappedUserID'
);

-- Discount code reserved by a stale pending purchase
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    500,
    0,
    true,
    'EXPIRE_EVENT_CHECKOUT_HOLDS_DISCOUNT',
    :'eventID',
    'fixed_amount',
    'Expire Checkout Holds Discount'
);

-- Checkout attendee answers held by a stale purchase
insert into event_attendee (
    event_id,
    manually_invited,
    registration_answers,
    status,
    user_id
) values (
    :'eventID',
    false,
    '{"answers": [{"question_id": "f30d0000-0000-0000-0000-00000000001d", "value": "Pending"}]}'::jsonb,
    'registration-questions-pending',
    :'pendingAttendeeUserID'
);

-- Direct-charge pending purchases covering stale, future, discounted and offer-linked holds
insert into event_purchase (
    admission_offer_id,
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
    hold_expires_at,
    payment_provider_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    provider_checkout_session_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values
    (
        null,
        2500,
        'direct-charge',
        'acct_expire_event_checkout_holds',
        'USD',
        0,
        null,
        null,
        :'eventID',
        :'directPurchaseID',
        :'ticketTypeID',
        current_timestamp - interval '2 hours',
        'stripe',
        0,
        0,
        'expire-event-checkout-holds-direct-session',
        'acct_expire_event_checkout_holds',
        '{"connected_account_id":"acct_expire_event_checkout_holds","display_name":"Expire Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'inclusive',
        'manual',
        'professional-event-admission',
        'Direct expired admission',
        :'directUserID',
        '{}'::jsonb
    ),
    (
        null,
        2000,
        'direct-charge',
        'acct_expire_event_checkout_holds',
        'USD',
        500,
        'EXPIRE_EVENT_CHECKOUT_HOLDS_DISCOUNT',
        :'discountCodeID',
        :'eventID',
        :'discountPurchaseID',
        :'ticketTypeID',
        current_timestamp - interval '2 hours',
        'stripe',
        0,
        0,
        'expire-event-checkout-holds-discount-session',
        'acct_expire_event_checkout_holds',
        '{"connected_account_id":"acct_expire_event_checkout_holds","display_name":"Expire Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'inclusive',
        'manual',
        'professional-event-admission',
        'Discount expired admission',
        :'discountUserID',
        '{}'::jsonb
    ),
    (
        null,
        2500,
        'direct-charge',
        'acct_expire_event_checkout_holds',
        'USD',
        0,
        null,
        null,
        :'eventID',
        :'futurePurchaseID',
        :'ticketTypeID',
        current_timestamp + interval '2 hours',
        'stripe',
        0,
        0,
        'expire-event-checkout-holds-future-session',
        'acct_expire_event_checkout_holds',
        '{"connected_account_id":"acct_expire_event_checkout_holds","display_name":"Expire Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'inclusive',
        'manual',
        'professional-event-admission',
        'Future admission',
        :'futureUserID',
        '{}'::jsonb
    ),
    (
        null,
        2500,
        'direct-charge',
        'acct_expire_event_checkout_holds',
        'USD',
        0,
        null,
        null,
        :'otherEventID',
        :'otherPurchaseID',
        :'otherTicketTypeID',
        current_timestamp - interval '2 hours',
        'stripe',
        0,
        0,
        'expire-event-checkout-holds-other-session',
        'acct_expire_event_checkout_holds',
        '{"connected_account_id":"acct_expire_event_checkout_holds","display_name":"Expire Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'inclusive',
        'manual',
        'professional-event-admission',
        'Other event admission',
        :'otherUserID',
        '{}'::jsonb
    ),
    (
        null,
        2500,
        'direct-charge',
        'acct_expire_event_checkout_holds',
        'USD',
        0,
        null,
        null,
        :'eventID',
        :'pastPurchaseID',
        :'ticketTypeID',
        current_timestamp - interval '2 hours',
        'stripe',
        0,
        0,
        'expire-event-checkout-holds-past-session',
        'acct_expire_event_checkout_holds',
        '{"connected_account_id":"acct_expire_event_checkout_holds","display_name":"Expire Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'inclusive',
        'manual',
        'professional-event-admission',
        'Past admission',
        :'pastUserID',
        '{}'::jsonb
    ),
    (
        null,
        2500,
        'direct-charge',
        'acct_expire_event_checkout_holds',
        'USD',
        0,
        null,
        null,
        :'eventID',
        :'pendingAttendeePurchaseID',
        :'ticketTypeID',
        current_timestamp - interval '2 hours',
        'stripe',
        0,
        0,
        'expire-event-checkout-holds-attendee-session',
        'acct_expire_event_checkout_holds',
        '{"connected_account_id":"acct_expire_event_checkout_holds","display_name":"Expire Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'inclusive',
        'manual',
        'professional-event-admission',
        'Pending attendee admission',
        :'pendingAttendeeUserID',
        '{}'::jsonb
    ),
    (
        :'cappedOfferID',
        2500,
        'direct-charge',
        'acct_expire_event_checkout_holds',
        'USD',
        0,
        null,
        null,
        :'eventID',
        :'cappedPurchaseID',
        :'ticketTypeID',
        current_timestamp + interval '2 hours',
        'stripe',
        0,
        0,
        'expire-event-checkout-holds-capped-session',
        'acct_expire_event_checkout_holds',
        '{"connected_account_id":"acct_expire_event_checkout_holds","display_name":"Expire Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'inclusive',
        'manual',
        'professional-event-admission',
        'Offer capped admission',
        :'cappedUserID',
        '{}'::jsonb
    );

-- External pending purchase whose payment window has expired
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    2500,
    'external',
    'USD',
    :'eventID',
    :'expiredExternalPurchaseID',
    :'ticketTypeID',
    current_timestamp - interval '2 hours',
    'pending',
    'External expired admission',
    :'expiredExternalUserID'
);

-- Free pending purchase whose hold has expired
insert into event_purchase (
    amount_minor,
    charge_model,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    0,
    'ocg-free',
    :'eventID',
    :'freePurchaseID',
    :'ticketTypeID',
    current_timestamp - interval '2 hours',
    'pending',
    'Free expired admission',
    :'freeUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Expire the event checkout holds once before asserting persisted state
select expire_event_checkout_holds(
    (select e from event e where e.event_id = :'eventID'),
    (select g from "group" g where g.group_id = :'groupID'),
    '{"brand": "expire-event-checkout-holds"}'::jsonb
);

-- Should cap offer-expired checkout holds to now
select results_eq(
    format(
        $$
            select status, hold_expires_at
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'cappedPurchaseID'
    ),
    $$ values ('expired'::text, current_timestamp) $$,
    'Should cap offer-expired checkout holds to now'
);

-- Should delete checkout attendee hold rows
select is(
    (
        select count(*)::int
        from event_attendee
        where event_id = :'eventID'
        and user_id = :'pendingAttendeeUserID'
    ),
    0,
    'Should delete checkout attendee hold rows'
);

-- Should expire non-external checkout holds without notifications
select results_eq(
    format(
        $$
            select
                (select status from event_purchase where event_purchase_id = %L::uuid),
                (select status from event_purchase where event_purchase_id = %L::uuid),
                (
                    select count(*)::int
                    from notification n
                    where n.kind = 'event-external-payment-expired'
                    and n.user_id = any(array[%L::uuid, %L::uuid])
                )
        $$,
        :'directPurchaseID',
        :'freePurchaseID',
        :'directUserID',
        :'freeUserID'
    ),
    $$ values ('expired'::text, 'expired'::text, 0::int) $$,
    'Should expire non-external checkout holds without notifications'
);

-- Should expire past checkout holds without moving their deadline
select results_eq(
    format(
        $$
            select status, hold_expires_at
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'pastPurchaseID'
    ),
    $$ values ('expired'::text, current_timestamp - interval '2 hours') $$,
    'Should expire past checkout holds without moving their deadline'
);

-- Should leave future checkout holds pending
select results_eq(
    format(
        $$
            select status, hold_expires_at
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'futurePurchaseID'
    ),
    $$ values ('pending'::text, current_timestamp + interval '2 hours') $$,
    'Should leave future checkout holds pending'
);

-- Should leave other event holds pending
select is(
    (
        select status
        from event_purchase
        where event_purchase_id = :'otherPurchaseID'
    ),
    'pending',
    'Should leave other event holds pending'
);

-- Should notify expired external payment holders once
select is(
    (
        select count(*)::int
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-external-payment-expired'
        and n.user_id = :'expiredExternalUserID'
        and (ntd.data->>'event_purchase_id')::uuid = :'expiredExternalPurchaseID'::uuid
    ),
    1,
    'Should notify expired external payment holders once'
);

-- Should restore discount availability for expired discounted holds
select is(
    (
        select available
        from event_discount_code
        where event_discount_code_id = :'discountCodeID'
    ),
    1,
    'Should restore discount availability for expired discounted holds'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
