-- Tests counting allocated event ticket type seats.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set checkoutOfferID '0c130000-0000-0000-0000-000000000010'
\set collisionID '0c130000-0000-0000-0000-000000000016'
\set communityID '0c130000-0000-0000-0000-000000000001'
\set eventCategoryID '0c130000-0000-0000-0000-000000000002'
\set eventID '0c130000-0000-0000-0000-000000000003'
\set expiredOfferID '0c130000-0000-0000-0000-000000000014'
\set groupCategoryID '0c130000-0000-0000-0000-000000000004'
\set groupID '0c130000-0000-0000-0000-000000000005'
\set pendingOfferID '0c130000-0000-0000-0000-000000000011'
\set sharedOfferID '0c130000-0000-0000-0000-000000000017'
\set ticketTypeAllocatedID '0c130000-0000-0000-0000-000000000006'
\set ticketTypeCollisionID '0c130000-0000-0000-0000-000000000018'
\set ticketTypeEmptyID '0c130000-0000-0000-0000-000000000007'
\set ticketTypeSharedID '0c130000-0000-0000-0000-000000000019'
\set userCheckoutOfferID '0c130000-0000-0000-0000-000000000012'
\set userCollisionDirectID '0c130000-0000-0000-0000-00000000001a'
\set userCollisionOfferID '0c130000-0000-0000-0000-00000000001b'
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
\set userSharedDirect1ID '0c130000-0000-0000-0000-00000000001c'
\set userSharedDirect2ID '0c130000-0000-0000-0000-00000000001d'
\set userSharedOfferID '0c130000-0000-0000-0000-00000000001e'

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
select fx_user(:'userCollisionDirectID');
select fx_user(:'userCollisionOfferID');
select fx_user(:'userSharedDirect1ID');
select fx_user(:'userSharedDirect2ID');
select fx_user(:'userSharedOfferID');
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

-- Ticket type whose purchase and offer identifiers collide
select fx_event_ticket_type(:'ticketTypeCollisionID', :'eventID', jsonb_build_object(
    'order', 3,
    'seats_total', 8,
    'title', 'Collision pass'
));

-- Ticket type mixing direct purchases and purchases sharing an offer
select fx_event_ticket_type(:'ticketTypeSharedID', :'eventID', jsonb_build_object(
    'order', 4,
    'seats_total', 8,
    'title', 'Shared pass'
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

-- Completed offer whose identifier matches a direct purchase identifier
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
    discount_amount_minor,
    ticket_title
) values (
    :'collisionID',
    current_timestamp - interval '2 hours',
    :'eventID',
    :'ticketTypeCollisionID',
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'completed',
    :'userCollisionOfferID',

    0,
    0,
    'Collision pass'
);

-- Completed offer shared by several seat-holding purchases
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
    discount_amount_minor,
    ticket_title
) values (
    :'sharedOfferID',
    current_timestamp - interval '2 hours',
    :'eventID',
    :'ticketTypeSharedID',
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'completed',
    :'userSharedOfferID',

    0,
    0,
    'Shared pass'
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

-- Direct purchase whose identifier matches another purchase's offer identifier
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'collisionID',
    0,
    :'eventID',
    :'ticketTypeCollisionID',
    'completed',
    'Collision pass',
    :'userCollisionDirectID'
);

-- Purchase linked to the offer whose identifier collides with a purchase
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'collisionID',
    0,
    :'eventID',
    :'ticketTypeCollisionID',
    'completed',
    'Collision pass',
    :'userCollisionOfferID'
);

-- Direct purchases and purchases sharing one offer on the shared ticket type
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values
    (null, 0, :'eventID', :'ticketTypeSharedID', 'completed', 'Shared pass', :'userSharedDirect1ID'),
    (null, 0, :'eventID', :'ticketTypeSharedID', 'completed', 'Shared pass', :'userSharedDirect2ID'),
    (:'sharedOfferID', 0, :'eventID', :'ticketTypeSharedID', 'refund-pending', 'Shared pass', :'userSharedOfferID'),
    (:'sharedOfferID', 0, :'eventID', :'ticketTypeSharedID', 'refund-recovery-pending', 'Shared pass', :'userSharedOfferID');

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

-- Should count a purchase whose ID equals another purchase's offer ID as a separate seat
select is(
    get_event_ticket_type_allocated_seat_count(
        :'eventID'::uuid,
        :'ticketTypeCollisionID'::uuid
    ),
    2,
    'Should count a purchase whose ID equals another purchase''s offer ID as a separate seat'
);

-- Should count purchases without an offer individually and purchases sharing an offer once
select is(
    get_event_ticket_type_allocated_seat_count(
        :'eventID'::uuid,
        :'ticketTypeSharedID'::uuid
    ),
    3,
    'Should count purchases without an offer individually and purchases sharing an offer once'
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
