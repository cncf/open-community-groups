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

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userCompletedID');
select fx_user(:'userCheckoutOfferID');
select fx_user(:'userExpiredHoldID');
select fx_user(:'userExpiredID');
select fx_user(:'userExpiredOfferID');
select fx_user(:'userPendingID');
select fx_user(:'userPendingOfferID');
select fx_user(:'userRefundPendingID');
select fx_user(:'userRefundRecoveryID');
select fx_user(:'userRefundRequestedID');
select fx_user(:'userRefundedID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event for allocated seat count scenarios
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));

-- Ticket types with allocated and empty inventory
select fx_event_ticket_type(:'ticketTypeAllocatedID', :'eventID', jsonb_build_object(
    'seats_total', 8,
    'title', 'Allocated pass'
));
select fx_event_ticket_type(:'ticketTypeEmptyID', :'eventID', jsonb_build_object(
    'order', 2,
    'seats_total', 8
));

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
