-- Tests idempotent event enrollment reconciliation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(38);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set closedEventID '5e000000-0000-0000-0000-000000000027'
\set closedExpiredOfferID '5e000000-0000-0000-0000-000000000028'
\set closedExpiredUserID '5e000000-0000-0000-0000-000000000029'
\set closedQueueUserID '5e000000-0000-0000-0000-00000000002a'
\set closedTicketTypeID '5e000000-0000-0000-0000-00000000002b'
\set communityID '5e000000-0000-0000-0000-000000000001'
\set discountCodeID '5e000000-0000-0000-0000-000000000002'
\set dueDiscountCodeID '5e000000-0000-0000-0000-000000000023'
\set dueEventID '5e000000-0000-0000-0000-000000000003'
\set dueOfferID '5e000000-0000-0000-0000-000000000004'
\set duePurchaseID '5e000000-0000-0000-0000-000000000005'
\set dueTicketTypeID '5e000000-0000-0000-0000-000000000006'
\set dueUserID '5e000000-0000-0000-0000-000000000007'
\set eventCategoryID '5e000000-0000-0000-0000-000000000008'
\set externalExpiredEventID '5e000000-0000-0000-0000-000000000031'
\set externalExpiredPurchaseID '5e000000-0000-0000-0000-000000000032'
\set externalExpiredTicketTypeID '5e000000-0000-0000-0000-000000000033'
\set externalExpiredUserID '5e000000-0000-0000-0000-000000000034'
\set externalGroupID '5e000000-0000-0000-0000-000000000035'
\set externalReadyEventID '5e000000-0000-0000-0000-000000000036'
\set externalReadyTicketTypeID '5e000000-0000-0000-0000-000000000037'
\set externalReadyUserID '5e000000-0000-0000-0000-000000000038'
\set externalReminderEventID '5e000000-0000-0000-0000-000000000039'
\set externalReminderPurchaseID '5e000000-0000-0000-0000-00000000003a'
\set externalReminderTicketTypeID '5e000000-0000-0000-0000-00000000003b'
\set externalReminderUserID '5e000000-0000-0000-0000-00000000003c'
\set externalShortPurchaseID '5e000000-0000-0000-0000-000000000040'
\set externalShortUserID '5e000000-0000-0000-0000-000000000041'
\set externalUnreadyEventID '5e000000-0000-0000-0000-00000000003d'
\set externalUnreadyTicketTypeID '5e000000-0000-0000-0000-00000000003e'
\set externalUnreadyUserID '5e000000-0000-0000-0000-00000000003f'
\set freeEventID '5e000000-0000-0000-0000-000000000009'
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
\set replacementTicketTypeID '5e000000-0000-0000-0000-00000000001a'
\set replacementUserID '5e000000-0000-0000-0000-00000000001b'
\set retryEventID '5e000000-0000-0000-0000-00000000001c'
\set retryOfferID '5e000000-0000-0000-0000-00000000001d'
\set retryPurchaseID '5e000000-0000-0000-0000-00000000001e'
\set retryTicketTypeID '5e000000-0000-0000-0000-00000000001f'
\set retryUserID '5e000000-0000-0000-0000-000000000020'
\set rsvpEventID '5e000000-0000-0000-0000-000000000021'
\set rsvpUserID '5e000000-0000-0000-0000-000000000022'
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
select fx_user(:'externalExpiredUserID');
select fx_user(:'externalReadyUserID');
select fx_user(:'externalReminderUserID');
select fx_user(:'externalShortUserID');
select fx_user(:'externalUnreadyUserID');

-- Community
insert into site (description, site_id, theme, title)
values (
    'Enrollment reconciliation site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Enrollment Reconciliation Site'
);

-- Operator allowlist used by external-ready promotion and hold lifecycle
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Payment-ready group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_reconciliation", "seller_display_name": "Reconciliation Fiscal Sponsor"}'::jsonb));

-- Allowlisted group with external payments enabled for ready-event promotion
select fx_group(:'externalGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_external_reconcile", "seller_display_name": "External Fiscal Sponsor"}'::jsonb
));

-- Active events covering RSVP and ticket reconciliation paths
select fx_event(:'rsvpEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
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

-- External-ready paid event that promotes without a Stripe provider gate
select fx_event(:'externalReadyEventID', :'externalGroupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'external_payment_url', 'https://pay.example.test/ready-queue',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- External-marked event on a Stripe-ready group that is not externally eligible
select fx_event(:'externalUnreadyEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'external_payment_url', 'https://pay.example.test/unready-queue',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Event hosting an expired external pending hold
select fx_event(:'externalExpiredEventID', :'externalGroupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'external_payment_instructions', 'Pay by bank transfer',
    'external_payment_url', 'https://pay.example.test/expired-hold',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Event hosting a reminder-due external pending hold
select fx_event(:'externalReminderEventID', :'externalGroupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'external_payment_instructions', 'Pay by bank transfer',
    'external_payment_url', 'https://pay.example.test/reminder-hold',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
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
select fx_event_ticket_type(:'externalReadyTicketTypeID', :'externalReadyEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'externalUnreadyTicketTypeID', :'externalUnreadyEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'externalExpiredTicketTypeID', :'externalExpiredEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'externalReminderTicketTypeID', :'externalReminderEventID', jsonb_build_object('seats_total', 1));

-- Current prices, excluding the intentionally blocked no-price tier
select fx_event_ticket_price_window(gen_random_uuid(), :'freeTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(gen_random_uuid(), :'scopedTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(gen_random_uuid(), :'paidTicketTypeID', jsonb_build_object('amount_minor', 1000));
select fx_event_ticket_price_window(gen_random_uuid(), :'retryTicketTypeID', jsonb_build_object('amount_minor', 1000));
select fx_event_ticket_price_window(gen_random_uuid(), :'dueTicketTypeID', jsonb_build_object('amount_minor', 1000));
select fx_event_ticket_price_window(gen_random_uuid(), :'replacementTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(gen_random_uuid(), :'closedTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(gen_random_uuid(), :'externalReadyTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(gen_random_uuid(), :'externalUnreadyTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(gen_random_uuid(), :'externalExpiredTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(gen_random_uuid(), :'externalReminderTicketTypeID', jsonb_build_object('amount_minor', 5000));

-- RSVP events without a specialized ticket fixture use a default tier
select fx_event_ticket_type(gen_random_uuid(), e.event_id, jsonb_build_object(
    'seats_total', greatest(coalesce(e.capacity, 100), 1)
))
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free price for the RSVP event's default tier
select fx_event_ticket_price_window(gen_random_uuid(), ett.event_ticket_type_id, jsonb_build_object('amount_minor', 0))
from event_ticket_type ett
where ett.event_id = :'rsvpEventID'
and not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

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
    (select event_ticket_type_id from event_ticket_type where event_id = :'rsvpEventID' limit 1),
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
    :'externalReadyEventID',
    :'externalReadyTicketTypeID',
    :'externalReadyUserID'
), (
    '2024-01-01 00:00:00+00',
    :'externalUnreadyEventID',
    :'externalUnreadyTicketTypeID',
    :'externalUnreadyUserID'
);

-- Expired external hold that should enqueue an expiry notification
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
    :'externalExpiredEventID',
    :'externalExpiredPurchaseID',
    :'externalExpiredTicketTypeID',
    current_timestamp - interval '1 minute',
    0,
    0,
    'pending',
    'External expired admission',
    :'externalExpiredUserID'
);

-- Reminder-due external hold within 24 hours of its deadline
insert into event_purchase (
    amount_minor,
    charge_model,
    created_at,
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
    current_timestamp - interval '48 hours',
    'KRW',
    :'externalReminderEventID',
    :'externalReminderPurchaseID',
    :'externalReminderTicketTypeID',
    current_timestamp + interval '12 hours',
    0,
    0,
    'pending',
    'External reminder admission',
    :'externalReminderUserID'
);

-- Short external hold that should not receive a closing-soon reminder
insert into event_purchase (
    amount_minor,
    charge_model,
    created_at,
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
    current_timestamp,
    'KRW',
    :'externalReminderEventID',
    :'externalShortPurchaseID',
    :'externalReminderTicketTypeID',
    current_timestamp + interval '12 hours',
    0,
    0,
    'pending',
    'External short admission',
    :'externalShortUserID'
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

select ok(
    (
        select ntd.data @> jsonb_build_object(
            'amount_minor', 0,
            'dashboard_url', format(
                '/dashboard/user?tab=invitations#event-offer-%s',
                (
                    select ao.admission_offer_id
                    from admission_offer ao
                    where ao.event_id = :'freeEventID'::uuid
                    and ao.user_id = :'freeUser1ID'::uuid
                    and ao.status = 'pending'
                )
            ),
            'event_id', :'freeEventID',
            'event_ticket_type_id', :'freeTicketTypeID',
            'theme', jsonb_build_object('primary_color', '#2563eb'),
            'ticket_title', 'Free admission',
            'timezone', 'UTC',
            'user_id', :'freeUser1ID'
        )
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-ticket-waitlist-offer'
        and n.user_id = :'freeUser1ID'
    ),
    'Should enqueue complete ticket waitlist offer context'
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
    'ticket type not found',
    'Should reject a scoped ticket type owned by another event'
);

-- Should never skip a blocked queue head
select is(
    reconcile_event_enrollment(:'noPriceEventID'),
    array[]::uuid[],
    'Should stop when the FIFO head has no current price'
);

select results_eq(
    format(
        $$
            select user_id
            from event_waitlist
            where event_id = %L::uuid
            order by created_at, user_id
        $$,
        :'noPriceEventID'
    ),
    format(
        $$ values (%L::uuid), (%L::uuid) $$,
        :'noPriceUser1ID',
        :'noPriceUser2ID'
    ),
    'Should keep every no-price queue entry in place'
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

-- Should promote an external-ready paid queue without a Stripe provider
select is(
    reconcile_event_enrollment(:'externalReadyEventID'),
    array[:'externalReadyUserID'::uuid],
    'Should promote an external-ready paid queue without a Stripe provider'
);

-- Should leave an external-marked unready queue idle even with Stripe configured
select is(
    reconcile_event_enrollment(:'externalUnreadyEventID', null, 'stripe'),
    array[]::uuid[],
    'Should leave an external-marked unready queue idle even with Stripe configured'
);

-- Should keep the external-marked unready queue head in place
select results_eq(
    format(
        $$
            select user_id
            from event_waitlist
            where event_id = %L::uuid
            order by created_at, user_id
        $$,
        :'externalUnreadyEventID'
    ),
    format($$ values (%L::uuid) $$, :'externalUnreadyUserID'),
    'Should keep the external-marked unready queue head in place'
);

-- Should expire a due external pending hold
select is(
    reconcile_event_enrollment(:'externalExpiredEventID'),
    array[]::uuid[],
    'Should expire a due external pending hold'
);

-- Should mark the due external hold expired
select is(
    (
        select status
        from event_purchase
        where event_purchase_id = :'externalExpiredPurchaseID'
    ),
    'expired',
    'Should mark the due external hold expired'
);

-- Should enqueue one external payment expired notification
select is(
    (
        select count(*)::int
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-external-payment-expired'
        and n.user_id = :'externalExpiredUserID'
        and (ntd.data->>'event_purchase_id')::uuid = :'externalExpiredPurchaseID'::uuid
    ),
    1,
    'Should enqueue one external payment expired notification'
);

-- Should reconcile a reminder-due external hold
select is(
    reconcile_event_enrollment(:'externalReminderEventID'),
    array[]::uuid[],
    'Should reconcile a reminder-due external hold'
);

-- Should persist the reminder sent marker before retries
select ok(
    (
        select external_payment_reminder_sent_at is not null
        from event_purchase
        where event_purchase_id = :'externalReminderPurchaseID'
    ),
    'Should persist the reminder sent marker before retries'
);

-- Should enqueue exactly one external payment reminder notification
select is(
    (
        select count(*)::int
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-external-payment-reminder'
        and n.user_id = :'externalReminderUserID'
        and (ntd.data->>'event_purchase_id')::uuid = :'externalReminderPurchaseID'::uuid
    ),
    1,
    'Should enqueue exactly one external payment reminder notification'
);

-- Should not enqueue a duplicate external payment reminder
select is(
    reconcile_event_enrollment(:'externalReminderEventID'),
    array[]::uuid[],
    'Should not enqueue a duplicate external payment reminder'
);

-- Should keep a single external payment reminder after repeated reconciliation
select is(
    (
        select count(*)::int
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-external-payment-reminder'
        and n.user_id = :'externalReminderUserID'
        and (ntd.data->>'event_purchase_id')::uuid = :'externalReminderPurchaseID'::uuid
    ),
    1,
    'Should keep a single external payment reminder after repeated reconciliation'
);

-- Should not mark a short external hold as reminder-sent
select ok(
    (
        select external_payment_reminder_sent_at is null
        from event_purchase
        where event_purchase_id = :'externalShortPurchaseID'
    ),
    'Should not mark a short external hold as reminder-sent'
);

-- Should not enqueue a closing-soon reminder for a hold shorter than 24 hours
select is(
    (
        select count(*)::int
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-external-payment-reminder'
        and n.user_id = :'externalShortUserID'
        and (ntd.data->>'event_purchase_id')::uuid = :'externalShortPurchaseID'::uuid
    ),
    0,
    'Should not enqueue a closing-soon reminder for a hold shorter than 24 hours'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
