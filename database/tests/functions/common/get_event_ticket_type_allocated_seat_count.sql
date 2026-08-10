-- Tests counting allocated event ticket type seats.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set checkoutOfferID '0c130000-0000-0000-0000-000000000010'
\set communityID '0c130000-0000-0000-0000-000000000001'
\set eventCategoryID '0c130000-0000-0000-0000-000000000002'
\set eventID '0c130000-0000-0000-0000-000000000003'
\set expiredOfferID '0c130000-0000-0000-0000-000000000014'
\set groupCategoryID '0c130000-0000-0000-0000-000000000004'
\set groupID '0c130000-0000-0000-0000-000000000005'
\set pendingOfferID '0c130000-0000-0000-0000-000000000011'
\set ticketTypeAllocatedID '0c130000-0000-0000-0000-000000000006'
\set ticketTypeEmptyID '0c130000-0000-0000-0000-000000000007'
\set userCheckoutOfferID '0c130000-0000-0000-0000-000000000012'
\set userCompletedID '0c130000-0000-0000-0000-000000000008'
\set userExpiredHoldID '0c130000-0000-0000-0000-000000000009'
\set userExpiredID '0c130000-0000-0000-0000-00000000000a'
\set userExpiredOfferID '0c130000-0000-0000-0000-000000000015'
\set userPendingID '0c130000-0000-0000-0000-00000000000b'
\set userPendingOfferID '0c130000-0000-0000-0000-000000000013'
\set userRefundedID '0c130000-0000-0000-0000-00000000000f'
\set userRefundPendingID '0c130000-0000-0000-0000-00000000000c'
\set userRefundRecoveryID '0c130000-0000-0000-0000-00000000000d'
\set userRefundRequestedID '0c130000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for allocated seat count scenarios
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
    'allocated-seat-community',
    'Allocated Seat Community',
    'Community for allocated ticket seat tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category for allocated seat count scenarios
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category for allocated seat count scenarios
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group for allocated seat count scenarios
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Allocated Seat Group',
    'allocated-seat-group'
);

-- Users covering every purchase lifecycle state
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'userCompletedID', 'hash-1', 'completed@example.test', true, 'completed-user'),
    (
        :'userCheckoutOfferID',
        'hash-offer-checkout',
        'offer-checkout@example.test',
        true,
        'offer-checkout-user'
    ),
    (:'userExpiredHoldID', 'hash-2', 'expired-hold@example.test', true, 'expired-hold-user'),
    (:'userExpiredID', 'hash-3', 'expired@example.test', true, 'expired-user'),
    (
        :'userExpiredOfferID',
        'hash-expired-offer',
        'expired-offer@example.test',
        true,
        'expired-offer-user'
    ),
    (:'userPendingID', 'hash-4', 'pending@example.test', true, 'pending-user'),
    (
        :'userPendingOfferID',
        'hash-offer-pending',
        'offer-pending@example.test',
        true,
        'offer-pending-user'
    ),
    (:'userRefundPendingID', 'hash-5', 'refund-pending@example.test', true, 'refund-pending-user'),
    (:'userRefundRecoveryID', 'hash-6', 'refund-recovery@example.test', true, 'refund-recovery-user'),
    (:'userRefundRequestedID', 'hash-7', 'refund-requested@example.test', true, 'refund-requested-user'),
    (:'userRefundedID', 'hash-8', 'refunded@example.test', true, 'refunded-user');

-- Event for allocated seat count scenarios
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values (
    :'eventID',
    'Event for allocated ticket seat tests',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Allocated Seat Event',
    'USD',
    'allocated-seat-event',
    'UTC'
);

-- Ticket types with allocated and empty inventory
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values
    (:'ticketTypeAllocatedID', :'eventID', 1, 8, 'Allocated pass'),
    (:'ticketTypeEmptyID', :'eventID', 2, 8, 'Empty pass');

-- Offers covering unclaimed and checkout-pending reservations
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
    :'pendingOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeAllocatedID',
    current_timestamp + interval '1 hour',
    'waitlist',
    'pending',
    :'userPendingOfferID',

    null,
    null,
    null,
    null
), (
    :'checkoutOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeAllocatedID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    :'userCheckoutOfferID',

    1000,
    'USD',
    0,
    'Allocated pass'
), (
    :'expiredOfferID',
    current_timestamp - interval '2 hours',
    :'eventID',
    :'ticketTypeAllocatedID',
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'pending',
    :'userExpiredOfferID',

    null,
    null,
    null,
    null
);

-- Purchases covering allocating and non-allocating lifecycle states
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (
        null,
        0,
        'USD',
        :'eventID',
        :'ticketTypeAllocatedID',
        null,
        'completed',
        'Allocated pass',
        :'userCompletedID'
    ),
    (
        null,
        0,
        'USD',
        :'eventID',
        :'ticketTypeAllocatedID',
        current_timestamp - interval '10 minutes',
        'pending',
        'Allocated pass',
        :'userExpiredHoldID'
    ),
    (
        null,
        0,
        'USD',
        :'eventID',
        :'ticketTypeAllocatedID',
        null,
        'expired',
        'Allocated pass',
        :'userExpiredID'
    ),
    (
        null,
        0,
        'USD',
        :'eventID',
        :'ticketTypeAllocatedID',
        current_timestamp + interval '10 minutes',
        'pending',
        'Allocated pass',
        :'userPendingID'
    ),
    (
        null,
        0,
        'USD',
        :'eventID',
        :'ticketTypeAllocatedID',
        null,
        'refund-pending',
        'Allocated pass',
        :'userRefundPendingID'
    ),
    (
        null,
        0,
        'USD',
        :'eventID',
        :'ticketTypeAllocatedID',
        null,
        'refund-recovery-pending',
        'Allocated pass',
        :'userRefundRecoveryID'
    ),
    (
        null,
        0,
        'USD',
        :'eventID',
        :'ticketTypeAllocatedID',
        null,
        'refund-requested',
        'Allocated pass',
        :'userRefundRequestedID'
    ),
    (
        null,
        0,
        'USD',
        :'eventID',
        :'ticketTypeAllocatedID',
        null,
        'refunded',
        'Allocated pass',
        :'userRefundedID'
    ),
    (
        :'checkoutOfferID',
        0,
        'USD',
        :'eventID',
        :'ticketTypeAllocatedID',
        current_timestamp + interval '10 minutes',
        'pending',
        'Allocated pass',
        :'userCheckoutOfferID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count active offers and purchases without expired offers or duplicate linked holds
select is(
    get_event_ticket_type_allocated_seat_count(
        :'eventID'::uuid,
        :'ticketTypeAllocatedID'::uuid
    ),
    7,
    'Should count active offers and purchases without expired offers or duplicate linked holds'
);

-- Should return zero for a ticket type without purchases
select is(
    get_event_ticket_type_allocated_seat_count(
        :'eventID'::uuid,
        :'ticketTypeEmptyID'::uuid
    ),
    0,
    'Should return zero for a ticket type without purchases'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
