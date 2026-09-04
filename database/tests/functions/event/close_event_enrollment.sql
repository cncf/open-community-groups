-- Tests closing active event enrollment reservations and queues.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '5e030000-0000-0000-0000-000000000001'
\set checkoutOfferID '5e030000-0000-0000-0000-000000000002'
\set checkoutPurchaseID '5e030000-0000-0000-0000-000000000003'
\set checkoutUserID '5e030000-0000-0000-0000-000000000004'
\set communityID '5e030000-0000-0000-0000-000000000005'
\set confirmedPurchaseID '5e030000-0000-0000-0000-000000000015'
\set confirmedUserID '5e030000-0000-0000-0000-000000000016'
\set directPurchaseID '5e030000-0000-0000-0000-000000000006'
\set directUserID '5e030000-0000-0000-0000-000000000007'
\set discountCodeID '5e030000-0000-0000-0000-000000000008'
\set eventCategoryID '5e030000-0000-0000-0000-000000000009'
\set externalEventID '5e030000-0000-0000-0000-000000000017'
\set externalPurchaseID '5e030000-0000-0000-0000-000000000018'
\set externalTicketTypeID '5e030000-0000-0000-0000-000000000019'
\set externalUserID '5e030000-0000-0000-0000-00000000001a'
\set groupCategoryID '5e030000-0000-0000-0000-00000000000a'
\set groupID '5e030000-0000-0000-0000-00000000000b'
\set offerID '5e030000-0000-0000-0000-00000000000c'
\set offerUserID '5e030000-0000-0000-0000-00000000000d'
\set priceWindowID '5e030000-0000-0000-0000-00000000000e'
\set queueEventID '5e030000-0000-0000-0000-00000000000f'
\set queueTicketTypeID '5e030000-0000-0000-0000-000000000010'
\set requestEventID '5e030000-0000-0000-0000-000000000011'
\set requestTicketTypeID '5e030000-0000-0000-0000-000000000012'
\set requestUserID '5e030000-0000-0000-0000-000000000013'
\set waitlistUserID '5e030000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'actorUserID');
select fx_user(:'checkoutUserID');
select fx_user(:'confirmedUserID');
select fx_user(:'directUserID');
select fx_user(:'externalUserID');
select fx_user(:'offerUserID');
select fx_user(:'requestUserID');
select fx_user(:'waitlistUserID');

-- Group that owns both enrollment closure events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_close", "seller_display_name": "Close Event Fiscal Sponsor"}'::jsonb));

-- Ticketed waitlist event with active offers and checkouts
select fx_event(:'queueEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Approval event with a pending ticket request
select fx_event(:'requestEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- External-payment event with a pending hold
select fx_event(:'externalEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/close',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Ticket tiers used by the queue and request events
select fx_event_ticket_type(:'queueTicketTypeID', :'queueEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'requestTicketTypeID', :'requestEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'externalTicketTypeID', :'externalEventID', jsonb_build_object('seats_total', 10));

-- Current price used by the active checkout snapshots
select fx_event_ticket_price_window(:'priceWindowID', :'queueTicketTypeID', jsonb_build_object('amount_minor', 1000));

-- Discount reserved by both active checkout purchases
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
    'CLOSE5',
    :'queueEventID',
    'fixed_amount',
    'Closure discount'
);

-- Active pending and checkout-pending admission offers
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id,

    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    ticket_title
) values
    (
        :'checkoutOfferID',
        :'queueEventID',
        :'queueTicketTypeID',
        current_timestamp + interval '1 hour',
        'approval',
        'checkout_pending',
        :'checkoutUserID',

        500,
        'USD',
        500,
        'CLOSE5',
        :'discountCodeID',
        'Queue admission'
    ),
    (
        :'offerID',
        :'queueEventID',
        :'queueTicketTypeID',
        current_timestamp + interval '1 hour',
        'waitlist',
        'pending',
        :'offerUserID',

        null,
        null,
        null,
        null,
        null,
        null
    );

-- Offer-linked and direct pending checkout purchases
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (
        :'checkoutOfferID',
        0,
        'USD',
        500,
        'CLOSE5',
        :'discountCodeID',
        :'queueEventID',
        :'checkoutPurchaseID',
        :'queueTicketTypeID',
        current_timestamp + interval '15 minutes',
        'pending',
        'Queue admission',
        :'checkoutUserID'
    ),
    (
        null,
        0,
        'USD',
        500,
        'CLOSE5',
        :'discountCodeID',
        :'queueEventID',
        :'directPurchaseID',
        :'queueTicketTypeID',
        current_timestamp + interval '15 minutes',
        'pending',
        'Queue admission',
        :'directUserID'
    );

-- Completed purchase preserved when enrollment closes
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    0,
    :'queueEventID',
    :'confirmedPurchaseID',
    :'queueTicketTypeID',
    'completed',
    'Queue admission',
    :'confirmedUserID'
);

-- Pending external purchase expired when enrollment closes
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    'KRW',
    :'externalEventID',
    :'externalPurchaseID',
    :'externalTicketTypeID',
    current_timestamp + interval '2 days',
    0,
    0,
    'pending',
    'External admission',
    :'externalUserID'
);

-- Checkout-created attendee holds released when pending purchases expire
insert into event_attendee (
    event_id,
    status,
    user_id
) values
    (
        :'queueEventID',
        'registration-questions-pending',
        :'checkoutUserID'
    ),
    (
        :'queueEventID',
        'registration-questions-pending',
        :'directUserID'
    );

-- Confirmed attendee preserved when enrollment closes
insert into event_attendee (
    event_id,
    status,
    user_id
) values (
    :'queueEventID',
    'confirmed',
    :'confirmedUserID'
);

-- FIFO queue cleared when enrollment closes
insert into event_waitlist (
    event_id,
    event_ticket_type_id,
    user_id
) values (
    :'queueEventID',
    :'queueTicketTypeID',
    :'waitlistUserID'
);

-- Pending approval request cleared when enrollment closes
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    status,
    user_id
) values (
    :'requestEventID',
    :'requestTicketTypeID',
    'pending',
    :'requestUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel active offers and clear checkout and queue reservations
select is(
    close_event_enrollment(:'actorUserID', :'queueEventID'),
    array[:'checkoutUserID'::uuid, :'offerUserID'::uuid],
    'Should cancel active offers and clear checkout and queue reservations'
);

select results_eq(
    format(
        $$
            select
                (
                    select array_agg(status order by admission_offer_id)
                    from admission_offer
                    where event_id = %L::uuid
                ),
                (
                    select array_agg(status order by event_purchase_id)
                    from event_purchase
                    where event_id = %L::uuid
                ),
                (
                    select available
                    from event_discount_code
                    where event_discount_code_id = %L::uuid
                ),
                (
                    select count(*)
                    from event_attendee
                    where event_id = %L::uuid
                    and status = 'registration-questions-pending'
                ),
                (
                    select count(*)
                    from event_waitlist
                    where event_id = %L::uuid
                )
        $$,
        :'queueEventID',
        :'queueEventID',
        :'discountCodeID',
        :'queueEventID',
        :'queueEventID'
    ),
    $$ values (
        array['canceled', 'canceled']::text[],
        array['expired', 'expired', 'completed']::text[],
        2,
        0::bigint,
        0::bigint
    ) $$,
    'Should expire checkouts, release discounts and attendee holds, and clear the queue'
);

-- Should preserve confirmed attendees and completed purchases
select results_eq(
    format(
        $$
            select
                ea.status,
                ep.status
            from event_attendee ea
            join event_purchase ep
                on ep.event_id = ea.event_id
                and ep.user_id = ea.user_id
            where ea.event_id = %L::uuid
            and ea.user_id = %L::uuid
            and ep.event_purchase_id = %L::uuid
        $$,
        :'queueEventID',
        :'confirmedUserID',
        :'confirmedPurchaseID'
    ),
    $$ values ('confirmed'::text, 'completed'::text) $$,
    'Should preserve confirmed attendees and completed purchases'
);

select is(
    (
        select count(*)::int
        from audit_log
        where event_id = :'queueEventID'::uuid
        and action = 'admission_offer_canceled'
    ),
    2,
    'Should audit each canceled admission offer'
);

select is(
    (
        select count(*)::int
        from notification
        where kind = 'event-admission-offer-canceled'
        and user_id in (:'checkoutUserID'::uuid, :'offerUserID'::uuid)
    ),
    2,
    'Should enqueue one cancellation notification per canceled offer'
);

-- Should expire pending external purchases and enqueue a do-not-pay notice
select is(
    close_event_enrollment(:'actorUserID', :'externalEventID'),
    array[]::uuid[],
    'Should expire pending external purchases and enqueue a do-not-pay notice'
);

select ok(
    exists(
        select 1
        from event_purchase ep
        join notification n
            on n.user_id = ep.user_id
            and n.kind = 'event-external-payment-expired'
        join notification_template_data ntd using (notification_template_data_id)
        where ep.event_purchase_id = :'externalPurchaseID'::uuid
        and ep.status = 'expired'
        and (ntd.data->>'do_not_pay')::boolean = true
        and (ntd.data->>'event_purchase_id')::uuid = :'externalPurchaseID'::uuid
    ),
    'Should expire pending external purchases and enqueue a do-not-pay notice'
);

-- Should clear pending approval requests
select is(
    close_event_enrollment(:'actorUserID', :'requestEventID'),
    array[]::uuid[],
    'Should close an event that only has pending approval requests'
);

select is(
    (
        select count(*)::int
        from event_invitation_request
        where event_id = :'requestEventID'::uuid
    ),
    0,
    'Should clear pending approval requests'
);

-- Should remain idempotent after enrollment is already closed
select is(
    close_event_enrollment(:'actorUserID', :'queueEventID'),
    array[]::uuid[],
    'Should remain idempotent after enrollment is already closed'
);

-- Should reject a missing event
select throws_ok(
    $$select close_event_enrollment(
        '5e030000-0000-0000-0000-000000000001'::uuid,
        '5e030000-0000-0000-0000-000000000099'::uuid
    )$$,
    'event not found',
    'Should reject a missing event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
