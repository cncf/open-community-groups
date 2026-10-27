-- Tests closing active event enrollment reservations and queues.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

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
\set eventCategoryID '5e030000-0000-0000-0000-000000000009'
\set externalEventID '5e030000-0000-0000-0000-000000000017'
\set externalPurchaseID '5e030000-0000-0000-0000-000000000018'
\set externalTicketTypeID '5e030000-0000-0000-0000-000000000019'
\set externalUserID '5e030000-0000-0000-0000-00000000001a'
\set groupCategoryID '5e030000-0000-0000-0000-00000000000a'
\set groupID '5e030000-0000-0000-0000-00000000000b'
\set missingEventID '5e030000-0000-0000-0000-000000000099'
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

-- Community owning every closed event
select fx_community(:'communityID');

-- Organizer who closes enrollment and issued the invitation offer
select fx_user(:'actorUserID');

-- User holding the checkout-pending approval offer
select fx_user(:'checkoutUserID');

-- User whose completed purchase survives the closure
select fx_user(:'confirmedUserID');

-- User holding a direct pending checkout
select fx_user(:'directUserID');

-- User holding the external payment hold
select fx_user(:'externalUserID');

-- User holding the pending invitation offer
select fx_user(:'offerUserID');

-- User with a pending approval request
select fx_user(:'requestUserID');

-- User waiting in the FIFO queue
select fx_user(:'waitlistUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group that owns every enrollment closure event
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_close", "seller_display_name": "Close Event Fiscal Sponsor"}'::jsonb));

-- External-payment event with a pending hold
select fx_event(:'externalEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/close',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

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

-- Ticket tier used by the external event
select fx_event_ticket_type(:'externalTicketTypeID', :'externalEventID', jsonb_build_object('seats_total', 10));

-- Ticket tier used by the queue event
select fx_event_ticket_type(:'queueTicketTypeID', :'queueEventID', jsonb_build_object('seats_total', 10));

-- Ticket tier used by the request event
select fx_event_ticket_type(:'requestTicketTypeID', :'requestEventID', jsonb_build_object('seats_total', 10));

-- Checkout-pending approval offer and pending organizer invitation offer
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
    organizer_user_id,
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

        0,
        null,
        0,
        null,
        'Queue admission'
    ),
    (
        :'offerID',
        :'queueEventID',
        :'queueTicketTypeID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'pending',
        :'offerUserID',

        null,
        null,
        null,
        :'actorUserID',
        null
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

-- Free price used by the active checkout snapshots
select fx_event_ticket_price_window(:'priceWindowID', :'queueTicketTypeID', jsonb_build_object('amount_minor', 0));

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

-- Offer-linked and direct pending checkout purchases
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
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
        0,
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
        0,
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

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel active offers and clear checkout and queue reservations
select is(
    close_event_enrollment(:'actorUserID', :'queueEventID'),
    array[:'checkoutUserID'::uuid, :'offerUserID'::uuid],
    'Should cancel active offers and clear checkout and queue reservations'
);

-- Should expire checkouts and clear the queue
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
                    select count(*)
                    from event_waitlist
                    where event_id = %L::uuid
                )
        $$,
        :'queueEventID',
        :'queueEventID',
        :'queueEventID'
    ),
    $$ values (
        array['canceled', 'canceled']::text[],
        array['expired', 'expired', 'completed']::text[],
        0::bigint
    ) $$,
    'Should expire checkouts and clear the queue'
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

-- Should audit each canceled admission offer
select results_eq(
    format(
        $$
            select
                action,
                actor_user_id,
                community_id,
                group_id,
                resource_type,
                resource_id,
                details
            from audit_log
            where event_id = %L::uuid
            and action in (
                'event_admission_offer_canceled',
                'event_attendee_invitation_canceled'
            )
            order by details->>'admission_offer_id'
        $$,
        :'queueEventID'
    ),
    format(
        $$
            values
                (
                    'event_admission_offer_canceled'::text,
                    %L::uuid,
                    %L::uuid,
                    %L::uuid,
                    'user'::text,
                    %L::uuid,
                    jsonb_build_object(
                        'admission_offer_id', %L::uuid,
                        'event_id', %L::uuid,
                        'event_ticket_type_id', %L::uuid,
                        'user_id', %L::uuid
                    )
                ),
                (
                    'event_attendee_invitation_canceled'::text,
                    %L::uuid,
                    %L::uuid,
                    %L::uuid,
                    'user'::text,
                    %L::uuid,
                    jsonb_build_object(
                        'admission_offer_id', %L::uuid,
                        'event_id', %L::uuid,
                        'event_ticket_type_id', %L::uuid,
                        'user_id', %L::uuid
                    )
                )
        $$,
        :'actorUserID',
        :'communityID',
        :'groupID',
        :'checkoutUserID',
        :'checkoutOfferID',
        :'queueEventID',
        :'queueTicketTypeID',
        :'checkoutUserID',
        :'actorUserID',
        :'communityID',
        :'groupID',
        :'offerUserID',
        :'offerID',
        :'queueEventID',
        :'queueTicketTypeID',
        :'offerUserID'
    ),
    'Should audit each canceled admission offer'
);

-- Should not write admission_offer_canceled audit rows
select is(
    (
        select count(*)::int
        from audit_log
        where event_id = :'queueEventID'::uuid
        and action = 'admission_offer_canceled'
    ),
    0,
    'Should not write admission_offer_canceled audit rows'
);

-- Should enqueue one cancellation notification per canceled offer
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

-- Should enqueue a do-not-pay notice with the original hold details
select results_eq(
    format(
        $$
            select
                ep.status,
                (ntd.data->>'do_not_pay')::boolean,
                (ntd.data->>'event_purchase_id')::uuid,
                (ntd.data->>'amount_minor')::bigint,
                ntd.data->>'currency_code',
                ntd.data->>'ticket_title',
                (ntd.data->>'deadline')::bigint
            from event_purchase ep
            join notification n
                on n.user_id = ep.user_id
                and n.kind = 'event-external-payment-expired'
            join notification_template_data ntd using (notification_template_data_id)
            where ep.event_purchase_id = %L::uuid
        $$,
        :'externalPurchaseID'
    ),
    format(
        $$
            values (
                'expired'::text,
                true,
                %L::uuid,
                5000::bigint,
                'KRW'::text,
                'External admission'::text,
                epoch_seconds(current_timestamp + interval '2 days')
            )
        $$,
        :'externalPurchaseID'
    ),
    'Should enqueue a do-not-pay notice with the original hold details'
);

-- Should close an event that only has pending approval requests
select is(
    close_event_enrollment(:'actorUserID', :'requestEventID'),
    array[]::uuid[],
    'Should close an event that only has pending approval requests'
);

-- Should clear pending approval requests
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
    format(
        $$select close_event_enrollment(%L::uuid, %L::uuid)$$,
        :'actorUserID',
        :'missingEventID'
    ),
    'P0001',
    'event not found',
    'Should reject a missing event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
