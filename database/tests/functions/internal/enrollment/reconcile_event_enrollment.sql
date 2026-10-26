-- Tests idempotent event enrollment reconciliation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(25);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '5e000000-0000-0000-0000-000000000042'
\set canceledPriceWindowID '5e000000-0000-0000-0000-000000000047'
\set canceledTicketTypeID '5e000000-0000-0000-0000-000000000043'
\set canceledUserID '5e000000-0000-0000-0000-000000000044'
\set closedEventID '5e000000-0000-0000-0000-000000000027'
\set closedExpiredOfferID '5e000000-0000-0000-0000-000000000028'
\set closedExpiredUserID '5e000000-0000-0000-0000-000000000029'
\set closedPriceWindowID '5e000000-0000-0000-0000-000000000048'
\set closedQueueUserID '5e000000-0000-0000-0000-00000000002a'
\set closedTicketTypeID '5e000000-0000-0000-0000-00000000002b'
\set communityID '5e000000-0000-0000-0000-000000000001'
\set discountCodeID '5e000000-0000-0000-0000-000000000002'
\set dueDiscountCodeID '5e000000-0000-0000-0000-000000000023'
\set dueEventID '5e000000-0000-0000-0000-000000000003'
\set dueOfferID '5e000000-0000-0000-0000-000000000004'
\set duePriceWindowID '5e000000-0000-0000-0000-000000000049'
\set duePurchaseID '5e000000-0000-0000-0000-000000000005'
\set dueTicketTypeID '5e000000-0000-0000-0000-000000000006'
\set dueUserID '5e000000-0000-0000-0000-000000000007'
\set eventCategoryID '5e000000-0000-0000-0000-000000000008'
\set freeEventID '5e000000-0000-0000-0000-000000000009'
\set freePriceWindowID '5e000000-0000-0000-0000-00000000004a'
\set freeTicketTypeID '5e000000-0000-0000-0000-00000000000a'
\set freeUser1ID '5e000000-0000-0000-0000-00000000000b'
\set freeUser2ID '5e000000-0000-0000-0000-00000000000c'
\set freeUser3ID '5e000000-0000-0000-0000-00000000000d'
\set groupCategoryID '5e000000-0000-0000-0000-00000000000e'
\set groupID '5e000000-0000-0000-0000-00000000000f'
\set noPriceEventID '5e000000-0000-0000-0000-000000000010'
\set noPriceTicketTypeID '5e000000-0000-0000-0000-000000000011'
\set noPriceUser1ID '5e000000-0000-0000-0000-000000000012'
\set noPriceUser2ID '5e000000-0000-0000-0000-000000000013'
\set paidEventID '5e000000-0000-0000-0000-000000000014'
\set paidPriceWindowID '5e000000-0000-0000-0000-00000000004b'
\set paidTicketTypeID '5e000000-0000-0000-0000-000000000015'
\set paidUserID '5e000000-0000-0000-0000-000000000016'
\set refundPendingEventID '5e000000-0000-0000-0000-00000000002c'
\set refundPendingOfferID '5e000000-0000-0000-0000-00000000002d'
\set refundPendingPurchaseID '5e000000-0000-0000-0000-00000000002e'
\set refundPendingTicketTypeID '5e000000-0000-0000-0000-00000000002f'
\set refundPendingUserID '5e000000-0000-0000-0000-000000000030'
\set replacementEventID '5e000000-0000-0000-0000-000000000017'
\set replacementExpiredOfferID '5e000000-0000-0000-0000-000000000018'
\set replacementExpiredUserID '5e000000-0000-0000-0000-000000000019'
\set replacementPriceWindowID '5e000000-0000-0000-0000-00000000004c'
\set replacementTicketTypeID '5e000000-0000-0000-0000-00000000001a'
\set replacementUserID '5e000000-0000-0000-0000-00000000001b'
\set retryEventID '5e000000-0000-0000-0000-00000000001c'
\set retryOfferID '5e000000-0000-0000-0000-00000000001d'
\set retryPriceWindowID '5e000000-0000-0000-0000-00000000004d'
\set retryPurchaseID '5e000000-0000-0000-0000-00000000001e'
\set retryTicketTypeID '5e000000-0000-0000-0000-00000000001f'
\set retryUserID '5e000000-0000-0000-0000-000000000020'
\set rsvpEventID '5e000000-0000-0000-0000-000000000021'
\set rsvpPriceWindowID '5e000000-0000-0000-0000-000000000045'
\set rsvpTicketTypeID '5e000000-0000-0000-0000-000000000046'
\set rsvpUserID '5e000000-0000-0000-0000-000000000022'
\set scopedPriceWindowID '5e000000-0000-0000-0000-00000000004e'
\set scopedTicketTypeID '5e000000-0000-0000-0000-000000000024'
\set scopedUserID '5e000000-0000-0000-0000-000000000025'
\set siteID '5e000000-0000-0000-0000-000000000026'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'canceledUserID');
select fx_user(:'dueUserID');
select fx_user(:'freeUser1ID');
select fx_user(:'freeUser2ID');
select fx_user(:'freeUser3ID');
select fx_user(:'noPriceUser1ID');
select fx_user(:'noPriceUser2ID');
select fx_user(:'paidUserID');
select fx_user(:'refundPendingUserID');
select fx_user(:'replacementExpiredUserID');
select fx_user(:'replacementUserID');
select fx_user(:'retryUserID');
select fx_user(:'rsvpUserID');
select fx_user(:'scopedUserID');
select fx_user(:'closedExpiredUserID');
select fx_user(:'closedQueueUserID');

-- Site theme passed to enrollment notifications
insert into site (description, site_id, theme, title)
values (
    'Enrollment reconciliation site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Enrollment Reconciliation Site'
);

-- Payment-ready group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_reconciliation", "seller_display_name": "Reconciliation Fiscal Sponsor"}'::jsonb));

-- Active events covering RSVP and ticket reconciliation paths
select fx_event(:'rsvpEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));
select fx_event(:'freeEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));
select fx_event(:'noPriceEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));
select fx_event(:'paidEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));
select fx_event(:'refundPendingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));
select fx_event(:'retryEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));
select fx_event(:'dueEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));
select fx_event(:'replacementEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));
select fx_event(:'closedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'registration_ends_at', current_timestamp - interval '1 hour',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Canceled published event whose free queue could otherwise be promoted
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Ticket tiers
select fx_event_ticket_type(:'freeTicketTypeID', :'freeEventID', jsonb_build_object(
    'seats_total', 2,
    'title', 'Free admission'
));
select fx_event_ticket_type(:'noPriceTicketTypeID', :'noPriceEventID', jsonb_build_object('seats_total', 2));
select fx_event_ticket_type(:'scopedTicketTypeID', :'noPriceEventID', jsonb_build_object(
    'order', 2,
    'seats_total', 1
));
select fx_event_ticket_type(:'paidTicketTypeID', :'paidEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'refundPendingTicketTypeID', :'refundPendingEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'retryTicketTypeID', :'retryEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'dueTicketTypeID', :'dueEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'replacementTicketTypeID', :'replacementEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'closedTicketTypeID', :'closedEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'canceledTicketTypeID', :'canceledEventID', jsonb_build_object('seats_total', 1));

-- Current prices, excluding the intentionally blocked no-price tier
select fx_event_ticket_price_window(:'freePriceWindowID', :'freeTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'scopedPriceWindowID', :'scopedTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'paidPriceWindowID', :'paidTicketTypeID', jsonb_build_object('amount_minor', 1000));
select fx_event_ticket_price_window(:'retryPriceWindowID', :'retryTicketTypeID', jsonb_build_object('amount_minor', 1000));
select fx_event_ticket_price_window(:'duePriceWindowID', :'dueTicketTypeID', jsonb_build_object('amount_minor', 1000));
select fx_event_ticket_price_window(:'replacementPriceWindowID', :'replacementTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'closedPriceWindowID', :'closedTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'canceledPriceWindowID', :'canceledTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Single-seat RSVP tier
select fx_event_ticket_type(:'rsvpTicketTypeID', :'rsvpEventID', jsonb_build_object('seats_total', 1));

-- Current free price for the RSVP tier
select fx_event_ticket_price_window(:'rsvpPriceWindowID', :'rsvpTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Limited discount reserved by the checkout whose offer deadline elapsed
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
    :'dueDiscountCodeID',
    1000,
    0,
    true,
    'DUEFREE',
    :'dueEventID',
    'fixed_amount',
    'Due checkout discount'
);

-- Limited discount reserved by the expired retry checkout
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
    'SAVE5',
    :'retryEventID',
    'fixed_amount',
    'Retry discount'
);

-- FIFO waitlists
insert into event_waitlist (
    created_at,
    event_id,
    event_ticket_type_id,
    user_id
) values (
    '2024-01-01 00:00:00+00',
    :'rsvpEventID',
    :'rsvpTicketTypeID',
    :'rsvpUserID'
), (
    '2024-01-01 00:00:00+00',
    :'freeEventID',
    :'freeTicketTypeID',
    :'freeUser1ID'
), (
    '2024-01-02 00:00:00+00',
    :'freeEventID',
    :'freeTicketTypeID',
    :'freeUser2ID'
), (
    '2024-01-03 00:00:00+00',
    :'freeEventID',
    :'freeTicketTypeID',
    :'freeUser3ID'
), (
    '2024-01-01 00:00:00+00',
    :'noPriceEventID',
    :'noPriceTicketTypeID',
    :'noPriceUser1ID'
), (
    '2024-01-02 00:00:00+00',
    :'noPriceEventID',
    :'noPriceTicketTypeID',
    :'noPriceUser2ID'
), (
    '2024-01-01 00:00:00+00',
    :'noPriceEventID',
    :'scopedTicketTypeID',
    :'scopedUserID'
), (
    '2024-01-01 00:00:00+00',
    :'paidEventID',
    :'paidTicketTypeID',
    :'paidUserID'
), (
    '2024-01-01 00:00:00+00',
    :'replacementEventID',
    :'replacementTicketTypeID',
    :'replacementUserID'
), (
    '2024-01-01 00:00:00+00',
    :'closedEventID',
    :'closedTicketTypeID',
    :'closedQueueUserID'
), (
    '2024-01-01 00:00:00+00',
    :'canceledEventID',
    :'canceledTicketTypeID',
    :'canceledUserID'
);

-- Checkout-pending offers with stale hold and deadline scenarios
insert into admission_offer (
    admission_offer_id,
    created_at,
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
) values (
    :'retryOfferID',
    current_timestamp - interval '10 minutes',
    :'retryEventID',
    :'retryTicketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    :'retryUserID',

    500,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    'Retry admission'
), (
    :'dueOfferID',
    current_timestamp - interval '2 hours',
    :'dueEventID',
    :'dueTicketTypeID',
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'checkout_pending',
    :'dueUserID',

    0,
    'USD',
    1000,
    'DUEFREE',
    :'dueDiscountCodeID',
    'Due admission'
), (
    :'replacementExpiredOfferID',
    current_timestamp - interval '2 hours',
    :'replacementEventID',
    :'replacementTicketTypeID',
    current_timestamp - interval '1 hour',
    'waitlist',
    'pending',
    :'replacementExpiredUserID',

    null,
    null,
    null,
    null,
    null,
    null
), (
    :'closedExpiredOfferID',
    current_timestamp - interval '2 hours',
    :'closedEventID',
    :'closedTicketTypeID',
    current_timestamp - interval '1 hour',
    'waitlist',
    'pending',
    :'closedExpiredUserID',

    null,
    null,
    null,
    null,
    null,
    null
);

-- Checkout-pending offer retained during an automatic purchase refund
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id,

    amount_minor,
    currency_code,
    discount_amount_minor,
    ticket_title
) values (
    :'refundPendingOfferID',
    current_timestamp - interval '10 minutes',
    :'refundPendingEventID',
    :'refundPendingTicketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    :'refundPendingUserID',

    1000,
    'USD',
    0,
    'Refund-pending admission'
);

-- Pending purchases linked to the checkout-pending offers
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
) values (
    :'retryOfferID',
    0,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'retryEventID',
    :'retryPurchaseID',
    :'retryTicketTypeID',
    current_timestamp - interval '1 minute',
    'pending',
    'Retry admission',
    :'retryUserID'
), (
    :'dueOfferID',
    0,
    'USD',
    1000,
    'DUEFREE',
    :'dueDiscountCodeID',
    :'dueEventID',
    :'duePurchaseID',
    :'dueTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'Due admission',
    :'dueUserID'
);

-- Refund-pending purchase that keeps its linked offer unavailable for retry
insert into event_purchase (
    admission_offer_id,
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
    :'refundPendingOfferID',
    0,
    'USD',
    0,
    :'refundPendingEventID',
    :'refundPendingPurchaseID',
    :'refundPendingTicketTypeID',
    'refund-pending',
    'Refund-pending admission',
    :'refundPendingUserID'
);

-- Checkout-created registration row released with the stale retry hold
insert into event_attendee (
    event_id,
    manually_invited,
    status,
    user_id
) values (
    :'retryEventID',
    false,
    'registration-questions-pending',
    :'retryUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should promote an eligible waitlist entry into an admission offer
select is(
    reconcile_event_enrollment(:'rsvpEventID'),
    array[:'rsvpUserID'::uuid],
    'Should promote an eligible waitlist entry'
);

select results_eq(
    format(
        $$
            select ao.status, count(ew.user_id)
            from admission_offer ao
            left join event_waitlist ew
                on ew.event_id = ao.event_id
                and ew.user_id = ao.user_id
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
            group by ao.status
        $$,
        :'rsvpEventID',
        :'rsvpUserID'
    ),
    $$ values ('pending'::text, 0::bigint) $$,
    'Should replace the queue entry with an admission offer'
);

-- Should fill free ticket capacity in FIFO order
select is(
    reconcile_event_enrollment(:'freeEventID'),
    array[:'freeUser1ID'::uuid, :'freeUser2ID'::uuid],
    'Should promote free ticket waitlist entries in FIFO order'
);

select results_eq(
    format(
        $$
            select
                (
                    select array_agg(user_id order by created_at, user_id)
                    from admission_offer
                    where event_id = %L::uuid
                    and status = 'pending'
                ),
                (
                    select array_agg(user_id order by created_at, user_id)
                    from event_waitlist
                    where event_id = %L::uuid
                )
        $$,
        :'freeEventID',
        :'freeEventID'
    ),
    format(
        $$ values (
            array[%L::uuid, %L::uuid],
            array[%L::uuid]
        ) $$,
        :'freeUser1ID',
        :'freeUser2ID',
        :'freeUser3ID'
    ),
    'Should reserve capacity for promoted users and retain the next queue entry'
);

select is(
    reconcile_event_enrollment(:'freeEventID'),
    array[]::uuid[],
    'Should be idempotent when no additional capacity is available'
);

select results_eq(
    format(
        $$
            select
                (
                    select count(*)
                    from notification n
                    where n.kind = 'event-ticket-waitlist-offer'
                    and n.notification_template_data_id in (
                        select ntd.notification_template_data_id
                        from notification_template_data ntd
                        where (ntd.data->>'event_id')::uuid = %L::uuid
                    )
                ),
                (
                    select count(*)
                    from audit_log al
                    where al.event_id = %L::uuid
                    and al.action = 'event_ticket_waitlist_offer_created'
                )
        $$,
        :'freeEventID',
        :'freeEventID'
    ),
    $$ values (2::bigint, 2::bigint) $$,
    'Should enqueue and audit each ticket waitlist offer exactly once'
);

-- Should pass the site theme to waitlist offer notifications
select is(
    (
        select ntd.data->'theme'
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-ticket-waitlist-offer'
        and n.user_id = :'freeUser1ID'
    ),
    '{"primary_color": "#2563eb"}'::jsonb,
    'Should pass the site theme to waitlist offer notifications'
);

-- Should limit promotion to a requested ticket tier
select is(
    reconcile_event_enrollment(:'noPriceEventID', :'scopedTicketTypeID'),
    array[:'scopedUserID'::uuid],
    'Should promote only the requested ticket tier'
);

select results_eq(
    format(
        $$
            select event_ticket_type_id, user_id
            from event_waitlist
            where event_id = %L::uuid
            order by created_at, user_id
        $$,
        :'noPriceEventID'
    ),
    format(
        $$ values
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid)
        $$,
        :'noPriceTicketTypeID',
        :'noPriceUser1ID',
        :'noPriceTicketTypeID',
        :'noPriceUser2ID'
    ),
    'Should leave other ticket-tier queues unchanged'
);

-- Should reject a scoped ticket type owned by another event
select throws_ok(
    format(
        $$select reconcile_event_enrollment(%L::uuid, %L::uuid)$$,
        :'freeEventID',
        :'dueTicketTypeID'
    ),
    'P0001',
    'ticket type not found',
    'Should reject a scoped ticket type owned by another event'
);

-- Should not promote queues of a canceled event
select is(
    reconcile_event_enrollment(:'canceledEventID'),
    array[]::uuid[],
    'Should not promote queues of a canceled event'
);

select results_eq(
    format(
        $$
            select user_id
            from event_waitlist
            where event_id = %L::uuid
        $$,
        :'canceledEventID'
    ),
    format($$ values (%L::uuid) $$, :'canceledUserID'),
    'Should keep the canceled event queue in place'
);

-- Should expire stale offers without promoting closed registration queues
select is(
    reconcile_event_enrollment(:'closedEventID'),
    array[]::uuid[],
    'Should return no promotions when registration is closed'
);

select results_eq(
    format(
        $$
            select
                (
                    select status
                    from admission_offer
                    where admission_offer_id = %L::uuid
                ),
                (
                    select count(*)
                    from event_waitlist
                    where event_id = %L::uuid
                    and user_id = %L::uuid
                ),
                (
                    select count(*)
                    from admission_offer
                    where event_id = %L::uuid
                    and user_id = %L::uuid
                    and status = 'pending'
                )
        $$,
        :'closedExpiredOfferID',
        :'closedEventID',
        :'closedQueueUserID',
        :'closedEventID',
        :'closedQueueUserID'
    ),
    $$ values ('expired'::text, 1::bigint, 0::bigint) $$,
    'Should expire stale offers and leave closed registration queues unpromoted'
);

select is(
    reconcile_event_enrollment(:'paidEventID'),
    array[]::uuid[],
    'Should stop a paid queue when server payment configuration is unavailable'
);

select is(
    reconcile_event_enrollment(:'paidEventID', null, 'stripe'),
    array[:'paidUserID'::uuid],
    'Should resume the blocked paid queue when payment configuration is ready'
);

-- Should return expired checkout offers to pending before their deadline
select is(
    reconcile_event_enrollment(:'retryEventID', null, 'stripe'),
    array[]::uuid[],
    'Should reconcile an expired checkout hold without promoting users'
);

select results_eq(
    format(
        $$
            select
                ao.status,
                ep.status,
                edc.available,
                exists (
                    select 1
                    from event_attendee ea
                    where ea.event_id = %L::uuid
                    and ea.user_id = %L::uuid
                )
            from admission_offer ao
            join event_purchase ep using (admission_offer_id)
            join event_discount_code edc
                on edc.event_discount_code_id = ep.event_discount_code_id
            where ao.admission_offer_id = %L::uuid
            and ep.event_purchase_id = %L::uuid
        $$,
        :'retryEventID',
        :'retryUserID',
        :'retryOfferID',
        :'retryPurchaseID'
    ),
    $$ values ('pending'::text, 'expired'::text, 1, false) $$,
    'Should release the stale hold and discount while preserving the offer'
);

-- Should reconcile an offer while its automatic refund is pending
select is(
    reconcile_event_enrollment(:'refundPendingEventID', null, 'stripe'),
    array[]::uuid[],
    'Should reconcile an offer while its automatic refund is pending'
);

-- Should keep the refund-pending offer unavailable for retry
select is(
    (select status from admission_offer where admission_offer_id = :'refundPendingOfferID'),
    'checkout_pending',
    'Should keep the refund-pending offer unavailable for retry'
);

-- Should expire checkout holds that outlive their offer deadline
select is(
    reconcile_event_enrollment(:'dueEventID'),
    array[]::uuid[],
    'Should reconcile a due checkout without promoting users'
);

select is(
    reconcile_event_enrollment(:'dueEventID'),
    array[]::uuid[],
    'Should keep repeated due checkout reconciliation idempotent'
);

select results_eq(
    format(
        $$
            select
                ao.status,
                ep.status,
                edc.available
            from admission_offer ao
            join event_purchase ep using (admission_offer_id)
            join event_discount_code edc
                on edc.event_discount_code_id = ep.event_discount_code_id
            where ao.admission_offer_id = %L::uuid
            and ep.event_purchase_id = %L::uuid
        $$,
        :'dueOfferID',
        :'duePurchaseID'
    ),
    $$ values ('expired'::text, 'expired'::text, 1) $$,
    'Should expire the due offer and hold while releasing its discount once'
);

-- Should replace an expired reservation from the same FIFO queue
select is(
    reconcile_event_enrollment(:'replacementEventID'),
    array[:'replacementUserID'::uuid],
    'Should replace an expired waitlist offer when capacity returns'
);

select results_eq(
    format(
        $$
            select status, user_id
            from admission_offer
            where event_id = %L::uuid
            order by created_at, admission_offer_id
        $$,
        :'replacementEventID'
    ),
    format(
        $$ values
            ('expired'::text, %L::uuid),
            ('pending'::text, %L::uuid)
        $$,
        :'replacementExpiredUserID',
        :'replacementUserID'
    ),
    'Should retain expired history and create one replacement offer'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
