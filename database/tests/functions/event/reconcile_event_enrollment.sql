-- Tests idempotent event enrollment reconciliation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(25);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set closedEventID '4a160000-0000-0000-0000-000000000027'
\set closedExpiredOfferID '4a160000-0000-0000-0000-000000000028'
\set closedExpiredUserID '4a160000-0000-0000-0000-000000000029'
\set closedQueueUserID '4a160000-0000-0000-0000-00000000002a'
\set closedTicketTypeID '4a160000-0000-0000-0000-00000000002b'
\set communityID '4a160000-0000-0000-0000-000000000001'
\set discountCodeID '4a160000-0000-0000-0000-000000000002'
\set dueDiscountCodeID '4a160000-0000-0000-0000-000000000023'
\set dueEventID '4a160000-0000-0000-0000-000000000003'
\set dueOfferID '4a160000-0000-0000-0000-000000000004'
\set duePurchaseID '4a160000-0000-0000-0000-000000000005'
\set dueTicketTypeID '4a160000-0000-0000-0000-000000000006'
\set dueUserID '4a160000-0000-0000-0000-000000000007'
\set eventCategoryID '4a160000-0000-0000-0000-000000000008'
\set freeEventID '4a160000-0000-0000-0000-000000000009'
\set freeTicketTypeID '4a160000-0000-0000-0000-00000000000a'
\set freeUser1ID '4a160000-0000-0000-0000-00000000000b'
\set freeUser2ID '4a160000-0000-0000-0000-00000000000c'
\set freeUser3ID '4a160000-0000-0000-0000-00000000000d'
\set groupCategoryID '4a160000-0000-0000-0000-00000000000e'
\set groupID '4a160000-0000-0000-0000-00000000000f'
\set noPriceEventID '4a160000-0000-0000-0000-000000000010'
\set noPriceTicketTypeID '4a160000-0000-0000-0000-000000000011'
\set noPriceUser1ID '4a160000-0000-0000-0000-000000000012'
\set noPriceUser2ID '4a160000-0000-0000-0000-000000000013'
\set paidEventID '4a160000-0000-0000-0000-000000000014'
\set paidTicketTypeID '4a160000-0000-0000-0000-000000000015'
\set paidUserID '4a160000-0000-0000-0000-000000000016'
\set refundPendingEventID '4a160000-0000-0000-0000-00000000002c'
\set refundPendingOfferID '4a160000-0000-0000-0000-00000000002d'
\set refundPendingPurchaseID '4a160000-0000-0000-0000-00000000002e'
\set refundPendingTicketTypeID '4a160000-0000-0000-0000-00000000002f'
\set refundPendingUserID '4a160000-0000-0000-0000-000000000030'
\set replacementEventID '4a160000-0000-0000-0000-000000000017'
\set replacementExpiredOfferID '4a160000-0000-0000-0000-000000000018'
\set replacementExpiredUserID '4a160000-0000-0000-0000-000000000019'
\set replacementTicketTypeID '4a160000-0000-0000-0000-00000000001a'
\set replacementUserID '4a160000-0000-0000-0000-00000000001b'
\set retryEventID '4a160000-0000-0000-0000-00000000001c'
\set retryOfferID '4a160000-0000-0000-0000-00000000001d'
\set retryPurchaseID '4a160000-0000-0000-0000-00000000001e'
\set retryTicketTypeID '4a160000-0000-0000-0000-00000000001f'
\set retryUserID '4a160000-0000-0000-0000-000000000020'
\set rsvpEventID '4a160000-0000-0000-0000-000000000021'
\set rsvpUserID '4a160000-0000-0000-0000-000000000022'
\set scopedTicketTypeID '4a160000-0000-0000-0000-000000000024'
\set scopedUserID '4a160000-0000-0000-0000-000000000025'
\set siteID '4a160000-0000-0000-0000-000000000026'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into site (description, site_id, theme, title)
values (
    'Enrollment reconciliation site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Enrollment Reconciliation Site'
);

insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'reconciliation-community',
    'Reconciliation Community',
    'Community for event enrollment reconciliation tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Categories
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Payment-ready group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    payment_recipient,
    slug
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Reconciliation Group',
    '{"provider": "stripe", "recipient_id": "acct_reconciliation", "seller_display_name": "Reconciliation Fiscal Sponsor"}'::jsonb,
    'reconciliation-group'
);

-- Enrollment users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'dueUserID', 'hash-due', 'due@example.test', true, 'due-user'),
    (:'freeUser1ID', 'hash-free-1', 'free-1@example.test', true, 'free-user-1'),
    (:'freeUser2ID', 'hash-free-2', 'free-2@example.test', true, 'free-user-2'),
    (:'freeUser3ID', 'hash-free-3', 'free-3@example.test', true, 'free-user-3'),
    (
        :'noPriceUser1ID',
        'hash-no-price-1',
        'no-price-1@example.test',
        true,
        'no-price-user-1'
    ),
    (
        :'noPriceUser2ID',
        'hash-no-price-2',
        'no-price-2@example.test',
        true,
        'no-price-user-2'
    ),
    (:'paidUserID', 'hash-paid', 'paid@example.test', true, 'paid-user'),
    (
        :'refundPendingUserID',
        'hash-refund-pending',
        'refund-pending@example.test',
        true,
        'refund-pending-user'
    ),
    (
        :'replacementExpiredUserID',
        'hash-expired',
        'expired@example.test',
        true,
        'expired-user'
    ),
    (
        :'replacementUserID',
        'hash-replacement',
        'replacement@example.test',
        true,
        'replacement-user'
    ),
    (:'retryUserID', 'hash-retry', 'retry@example.test', true, 'retry-user'),
    (:'rsvpUserID', 'hash-rsvp', 'rsvp@example.test', true, 'rsvp-user'),
    (:'scopedUserID', 'hash-scoped', 'scoped@example.test', true, 'scoped-user'),
    (
        :'closedExpiredUserID',
        'hash-closed-expired',
        'closed-expired@example.test',
        true,
        'closed-expired-user'
    ),
    (
        :'closedQueueUserID',
        'hash-closed-queue',
        'closed-queue@example.test',
        true,
        'closed-queue-user'
    );

-- Active events covering RSVP and ticket reconciliation paths
insert into event (
    event_id,
    capacity,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    registration_ends_at,
    slug,
    starts_at,
    timezone,
    waitlist_enabled
) values (
    :'rsvpEventID',
    1,
    'RSVP event for reconciliation',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'RSVP Reconciliation Event',
    null,
    true,
    null,
    'rsvp-reconciliation-event',
    current_timestamp + interval '2 days',
    'UTC',
    true
), (
    :'freeEventID',
    null,
    'Free ticket event for FIFO promotion',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Due Reconciliation Event',
    'USD',
    true,
    null,
    'free-reconciliation-event',
    current_timestamp + interval '2 days',
    'UTC',
    true
), (
    :'noPriceEventID',
    null,
    'Ticket event without a current price',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'No Price Reconciliation Event',
    null,
    true,
    null,
    'no-price-reconciliation-event',
    current_timestamp + interval '2 days',
    'UTC',
    true
), (
    :'paidEventID',
    null,
    'Paid ticket event for readiness blocking',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Paid Reconciliation Event',
    'USD',
    true,
    null,
    'paid-reconciliation-event',
    current_timestamp + interval '2 days',
    'UTC',
    true
), (
    :'refundPendingEventID',
    null,
    'Paid ticket event with an automatic refund in progress',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Refund-Pending Reconciliation Event',
    'USD',
    true,
    null,
    'refund-pending-reconciliation-event',
    current_timestamp + interval '2 days',
    'UTC',
    false
), (
    :'retryEventID',
    null,
    'Paid ticket event with an expired checkout hold',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Retry Reconciliation Event',
    'USD',
    true,
    null,
    'retry-reconciliation-event',
    current_timestamp + interval '2 days',
    'UTC',
    false
), (
    :'dueEventID',
    null,
    'Discounted ticket event with an expired offer deadline',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Due Reconciliation Event',
    null,
    true,
    null,
    'due-reconciliation-event',
    current_timestamp + interval '2 days',
    'UTC',
    false
), (
    :'replacementEventID',
    null,
    'Free ticket event requiring a replacement offer',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Replacement Reconciliation Event',
    null,
    true,
    null,
    'replacement-reconciliation-event',
    current_timestamp + interval '2 days',
    'UTC',
    true
), (
    :'closedEventID',
    null,
    'Ticket event with closed registration',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Closed Registration Reconciliation Event',
    null,
    true,
    current_timestamp - interval '1 hour',
    'closed-registration-reconciliation-event',
    current_timestamp + interval '2 days',
    'UTC',
    true
);

-- Ticket tiers
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'freeTicketTypeID',
    :'freeEventID',
    1,
    2,
    'Free admission'
), (
    :'noPriceTicketTypeID',
    :'noPriceEventID',
    1,
    2,
    'No price admission'
), (
    :'scopedTicketTypeID',
    :'noPriceEventID',
    2,
    1,
    'Scoped admission'
), (
    :'paidTicketTypeID',
    :'paidEventID',
    1,
    1,
    'Paid admission'
), (
    :'refundPendingTicketTypeID',
    :'refundPendingEventID',
    1,
    1,
    'Refund-pending admission'
), (
    :'retryTicketTypeID',
    :'retryEventID',
    1,
    1,
    'Retry admission'
), (
    :'dueTicketTypeID',
    :'dueEventID',
    1,
    1,
    'Due admission'
), (
    :'replacementTicketTypeID',
    :'replacementEventID',
    1,
    1,
    'Replacement admission'
), (
    :'closedTicketTypeID',
    :'closedEventID',
    1,
    1,
    'Closed registration admission'
);

-- Current prices, excluding the intentionally blocked no-price tier
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (gen_random_uuid(), 0, :'freeTicketTypeID'),
    (gen_random_uuid(), 0, :'scopedTicketTypeID'),
    (gen_random_uuid(), 1000, :'paidTicketTypeID'),
    (gen_random_uuid(), 1000, :'retryTicketTypeID'),
    (gen_random_uuid(), 1000, :'dueTicketTypeID'),
    (gen_random_uuid(), 0, :'replacementTicketTypeID'),
    (gen_random_uuid(), 0, :'closedTicketTypeID');

-- RSVP events without a specialized ticket fixture use a default tier
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
)
select
    e.event_id,
    gen_random_uuid(),
    1,
    greatest(coalesce(e.capacity, 100), 1),
    'General Admission'
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free price for the RSVP event's default tier
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
)
select 0, gen_random_uuid(), ett.event_ticket_type_id
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
