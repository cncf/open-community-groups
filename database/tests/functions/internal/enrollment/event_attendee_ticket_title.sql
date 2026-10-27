-- Tests resolving the ticket title an attendee holds for an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c1e10000-0000-0000-0000-000000000001'
\set declinedOfferID 'c1e10000-0000-0000-0000-000000000002'
\set eventCategoryID 'c1e10000-0000-0000-0000-000000000003'
\set eventID 'c1e10000-0000-0000-0000-000000000004'
\set groupCategoryID 'c1e10000-0000-0000-0000-000000000005'
\set groupID 'c1e10000-0000-0000-0000-000000000006'
\set latestPurchaseUserID 'c1e10000-0000-0000-0000-000000000007'
\set latestRefundedUserID 'c1e10000-0000-0000-0000-000000000016'
\set noTitleUserID 'c1e10000-0000-0000-0000-000000000008'
\set offerSnapshotOfferID 'c1e10000-0000-0000-0000-000000000009'
\set offerSnapshotUserID 'c1e10000-0000-0000-0000-000000000010'
\set pendingPurchaseUserID 'c1e10000-0000-0000-0000-000000000011'
\set refundedPurchaseUserID 'c1e10000-0000-0000-0000-000000000012'
\set refundInFlightUserID 'c1e10000-0000-0000-0000-000000000017'
\set seatHoldingOfferID 'c1e10000-0000-0000-0000-000000000013'
\set seatHoldingUserID 'c1e10000-0000-0000-0000-000000000014'
\set seatOverRefundUserID 'c1e10000-0000-0000-0000-000000000018'
\set ticketTypeID 'c1e10000-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the event
select fx_community(:'communityID');

-- User whose latest purchase replaces an earlier one whose refund is in flight
select fx_user(:'latestPurchaseUserID');

-- User whose purchases were all refunded
select fx_user(:'latestRefundedUserID');

-- User without purchases or completed offers
select fx_user(:'noTitleUserID');

-- User admitted through an offer carrying its own ticket title
select fx_user(:'offerSnapshotUserID');

-- User retrying checkout after a refunded purchase
select fx_user(:'pendingPurchaseUserID');

-- User whose only purchase was refunded
select fx_user(:'refundedPurchaseUserID');

-- User with a completed refund in flight and a newer never-completed purchase
select fx_user(:'refundInFlightUserID');

-- User holding a seat through a completed purchase
select fx_user(:'seatHoldingUserID');

-- User holding a seat next to a newer refunded purchase
select fx_user(:'seatOverRefundUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose attendees hold tickets
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Ticket tier snapshotted by the purchases and offers
select fx_event_ticket_type(:'ticketTypeID', :'eventID');

-- Declined offer that never admitted the user without a title
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    source,
    status,
    user_id,

    amount_minor,
    discount_amount_minor,
    expires_at,
    ticket_title
) values (
    :'declinedOfferID',
    :'eventID',
    :'ticketTypeID',
    'approval',
    'declined',
    :'noTitleUserID',

    0,
    0,
    current_timestamp + interval '1 day',
    'Declined offer'
);

-- Completed offer with a ticket title snapshot
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    source,
    status,
    user_id,

    amount_minor,
    discount_amount_minor,
    expires_at,
    ticket_title
) values (
    :'offerSnapshotOfferID',
    :'eventID',
    :'ticketTypeID',
    'approval',
    'completed',
    :'offerSnapshotUserID',

    0,
    0,
    current_timestamp + interval '1 day',
    'Offer snapshot'
);

-- Completed offer outranked by the user's seat-holding purchase
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    source,
    status,
    user_id,

    amount_minor,
    discount_amount_minor,
    expires_at,
    ticket_title
) values (
    :'seatHoldingOfferID',
    :'eventID',
    :'ticketTypeID',
    'approval',
    'completed',
    :'seatHoldingUserID',

    0,
    0,
    current_timestamp + interval '1 day',
    'Outranked offer'
);

-- Purchases covering seat-holding, refunded, pending and replaced snapshots
insert into event_purchase (
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    hold_expires_at
) values
    (
        0,
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refund-pending',
        'Earlier ticket',
        :'latestPurchaseUserID',

        null
    ),
    (
        0,
        current_timestamp - interval '1 day',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'completed',
        'Latest ticket',
        :'latestPurchaseUserID',

        null
    ),
    (
        0,
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refunded',
        'Refunded before retry',
        :'pendingPurchaseUserID',

        null
    ),
    (
        0,
        current_timestamp - interval '1 day',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'pending',
        'Pending retry',
        :'pendingPurchaseUserID',

        current_timestamp + interval '10 minutes'
    ),
    (
        0,
        current_timestamp - interval '1 day',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refunded',
        'Refunded ticket',
        :'refundedPurchaseUserID',

        null
    ),
    (
        0,
        current_timestamp - interval '1 day',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'completed',
        'Seat ticket',
        :'seatHoldingUserID',

        null
    );

-- Purchases covering the refunded-only, refund-in-flight and seat-over-refund edges
insert into event_purchase (
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    completed_at
) values
    (
        0,
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refunded',
        'Earlier refunded ticket',
        :'latestRefundedUserID',

        current_timestamp - interval '2 days'
    ),
    (
        0,
        current_timestamp - interval '1 day',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refunded',
        'Latest refunded ticket',
        :'latestRefundedUserID',

        current_timestamp - interval '1 day'
    ),
    (
        0,
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refund-pending',
        'Completed refund in flight',
        :'refundInFlightUserID',

        current_timestamp - interval '2 days'
    ),
    (
        0,
        current_timestamp - interval '1 day',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refund-pending',
        'Never completed',
        :'refundInFlightUserID',

        null
    ),
    (
        0,
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'completed',
        'Older seat ticket',
        :'seatOverRefundUserID',

        current_timestamp - interval '2 days'
    ),
    (
        0,
        current_timestamp - interval '1 day',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refunded',
        'Newer refunded ticket',
        :'seatOverRefundUserID',

        current_timestamp - interval '1 day'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should fall back to the completed offer ticket title
select is(
    event_attendee_ticket_title(:'eventID'::uuid, :'offerSnapshotUserID'::uuid),
    'Offer snapshot',
    'Should fall back to the completed offer ticket title'
);

-- Should fall back to the latest refunded purchase when no purchase holds a seat
select is(
    event_attendee_ticket_title(:'eventID'::uuid, :'latestRefundedUserID'::uuid),
    'Latest refunded ticket',
    'Should fall back to the latest refunded purchase when no purchase holds a seat'
);

-- Should ignore pending purchases
select is(
    event_attendee_ticket_title(:'eventID'::uuid, :'pendingPurchaseUserID'::uuid),
    'Refunded before retry',
    'Should ignore pending purchases'
);

-- Should prefer a completed refund-in-flight purchase over a newer never-completed seat-holding purchase
select is(
    event_attendee_ticket_title(:'eventID'::uuid, :'refundInFlightUserID'::uuid),
    'Completed refund in flight',
    'Should prefer a completed refund-in-flight purchase over a newer never-completed seat-holding purchase'
);

-- Should prefer a seat-holding purchase over a newer refunded purchase
select is(
    event_attendee_ticket_title(:'eventID'::uuid, :'seatOverRefundUserID'::uuid),
    'Older seat ticket',
    'Should prefer a seat-holding purchase over a newer refunded purchase'
);

-- Should prefer the latest purchase
select is(
    event_attendee_ticket_title(:'eventID'::uuid, :'latestPurchaseUserID'::uuid),
    'Latest ticket',
    'Should prefer the latest purchase'
);

-- Should return null without purchases or completed offers
select is(
    event_attendee_ticket_title(:'eventID'::uuid, :'noTitleUserID'::uuid),
    null,
    'Should return null without purchases or completed offers'
);

-- Should return the refunded purchase title
select is(
    event_attendee_ticket_title(:'eventID'::uuid, :'refundedPurchaseUserID'::uuid),
    'Refunded ticket',
    'Should return the refunded purchase title'
);

-- Should return the seat-holding purchase title over a completed offer
select is(
    event_attendee_ticket_title(:'eventID'::uuid, :'seatHoldingUserID'::uuid),
    'Seat ticket',
    'Should return the seat-holding purchase title over a completed offer'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
