-- Tests resolving the enrollment facts of a user for an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvalRejectedUserID 'f20a0000-0000-0000-0000-000000000001'
\set approvalUserID 'f20a0000-0000-0000-0000-000000000002'
\set approvedRefundPurchaseID 'f20a0000-0000-0000-0000-00000000001c'
\set approvedRefundRequestID 'f20a0000-0000-0000-0000-00000000001d'
\set approvedRefundUserID 'f20a0000-0000-0000-0000-00000000001e'
\set canceledOfferID 'f20a0000-0000-0000-0000-000000000003'
\set communityID 'f20a0000-0000-0000-0000-000000000004'
\set confirmedPurchaseID 'f20a0000-0000-0000-0000-000000000005'
\set confirmedUserID 'f20a0000-0000-0000-0000-000000000006'
\set declinedUserID 'f20a0000-0000-0000-0000-000000000007'
\set eventCategoryID 'f20a0000-0000-0000-0000-000000000008'
\set eventID 'f20a0000-0000-0000-0000-000000000009'
\set expiredOfferID 'f20a0000-0000-0000-0000-00000000000a'
\set expiredOfferUserID 'f20a0000-0000-0000-0000-00000000000b'
\set groupCategoryID 'f20a0000-0000-0000-0000-00000000000c'
\set groupID 'f20a0000-0000-0000-0000-00000000000d'
\set invitedUserID 'f20a0000-0000-0000-0000-00000000000e'
\set newerAttendeeRefundPurchaseID 'f20a0000-0000-0000-0000-000000000023'
\set newerAttendeeRefundRequestID 'f20a0000-0000-0000-0000-000000000024'
\set newerAttendeeRefundUserID 'f20a0000-0000-0000-0000-000000000025'
\set offerID 'f20a0000-0000-0000-0000-00000000000f'
\set offerUserID 'f20a0000-0000-0000-0000-000000000010'
\set otherEventID 'f20a0000-0000-0000-0000-000000000022'
\set pendingPurchaseID 'f20a0000-0000-0000-0000-000000000011'
\set pendingPurchaseUserID 'f20a0000-0000-0000-0000-000000000012'
\set reattendedRefundPurchaseID 'f20a0000-0000-0000-0000-000000000026'
\set reattendedRefundRequestID 'f20a0000-0000-0000-0000-000000000027'
\set reattendedRefundUserID 'f20a0000-0000-0000-0000-000000000028'
\set refundRequestID 'f20a0000-0000-0000-0000-000000000013'
\set refundingOfferID 'f20a0000-0000-0000-0000-000000000014'
\set refundingPurchaseID 'f20a0000-0000-0000-0000-000000000015'
\set refundingUserID 'f20a0000-0000-0000-0000-000000000016'
\set rejectedRefundPurchaseID 'f20a0000-0000-0000-0000-00000000001f'
\set rejectedRefundRequestID 'f20a0000-0000-0000-0000-000000000020'
\set rejectedRefundUserID 'f20a0000-0000-0000-0000-000000000021'
\set registrationUserID 'f20a0000-0000-0000-0000-000000000017'
\set releasedRefundPurchaseID 'f20a0000-0000-0000-0000-000000000029'
\set releasedRefundRequestID 'f20a0000-0000-0000-0000-00000000002a'
\set releasedRefundUserID 'f20a0000-0000-0000-0000-00000000002b'
\set replacedRefundPurchaseID 'f20a0000-0000-0000-0000-00000000002c'
\set replacedRefundRequestID 'f20a0000-0000-0000-0000-00000000002d'
\set replacedRefundUserID 'f20a0000-0000-0000-0000-00000000002e'
\set replacementPurchaseID 'f20a0000-0000-0000-0000-00000000002f'
\set staleHoldPurchaseID 'f20a0000-0000-0000-0000-000000000018'
\set strangerUserID 'f20a0000-0000-0000-0000-000000000019'
\set ticketTypeID 'f20a0000-0000-0000-0000-00000000001a'
\set unstampedRefundPurchaseID 'f20a0000-0000-0000-0000-000000000030'
\set unstampedRefundRequestID 'f20a0000-0000-0000-0000-000000000031'
\set unstampedRefundUserID 'f20a0000-0000-0000-0000-000000000032'
\set waitlistedUserID 'f20a0000-0000-0000-0000-00000000001b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the event
select fx_community(:'communityID');

-- User with a rejected invitation request
select fx_user(:'approvalRejectedUserID');

-- User with a pending invitation request
select fx_user(:'approvalUserID');

-- User whose refunded purchase has an approved refund request
select fx_user(:'approvedRefundUserID');

-- Confirmed and checked-in attendee
select fx_user(:'confirmedUserID');

-- Attendee who declined an organizer invitation
select fx_user(:'declinedUserID');

-- User whose latest admission offer lapsed
select fx_user(:'expiredOfferUserID');

-- Attendee with a pending organizer invitation
select fx_user(:'invitedUserID');

-- User whose refunded purchase predates a later, canceled attendee row
select fx_user(:'newerAttendeeRefundUserID');

-- User with an active organizer invitation offer
select fx_user(:'offerUserID');

-- User with an unexpired pending purchase
select fx_user(:'pendingPurchaseUserID');

-- User attending again, without a new purchase, after a refunded purchase
select fx_user(:'reattendedRefundUserID');

-- User whose offer purchase is being refunded
select fx_user(:'refundingUserID');

-- Confirmed attendee whose refund request was rejected
select fx_user(:'rejectedRefundUserID');

-- Attendee waiting on registration answers with a stale checkout hold
select fx_user(:'registrationUserID');

-- User whose refunded purchase released the attendance
select fx_user(:'releasedRefundUserID');

-- Attendee whose seat is held by a purchase older than a refunded one
select fx_user(:'replacedRefundUserID');

-- User with no enrollment state
select fx_user(:'strangerUserID');

-- User whose refunded purchase has no refund time and predates a later
-- attendee row
select fx_user(:'unstampedRefundUserID');

-- Waitlisted user
select fx_user(:'waitlistedUserID');

-- Event category of the event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category of the group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event every enrollment fact belongs to
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Other event where the confirmed user only has a pending invitation
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Attendee rows: confirmed and checked in, registration pending, invited,
-- declined, confirmed with a rejected refund request, and the confirmed user's
-- pending invitation on the other event
insert into event_attendee (event_id, user_id, checked_in, manually_invited, status)
values
    (:'eventID', :'confirmedUserID', true, true, 'confirmed'),
    (:'eventID', :'registrationUserID', false, false, 'registration-questions-pending'),
    (:'eventID', :'invitedUserID', false, true, 'invitation-pending'),
    (:'eventID', :'declinedUserID', false, true, 'invitation-rejected'),
    (:'eventID', :'rejectedRefundUserID', false, false, 'confirmed'),
    (:'otherEventID', :'confirmedUserID', false, true, 'invitation-pending');

-- Attendee rows with explicit timelines: canceled after the refund was
-- recorded, revived after a refund, released by the refund, kept by a
-- replacement purchase, and canceled after an unstamped refund
insert into event_attendee (
    attendance_canceled_at,
    created_at,
    event_id,
    status,
    user_id
) values
    (current_timestamp - interval '1 day', current_timestamp - interval '2 days', :'eventID', 'attendance-canceled', :'newerAttendeeRefundUserID'),
    (null, current_timestamp - interval '5 days', :'eventID', 'confirmed', :'reattendedRefundUserID'),
    (current_timestamp - interval '1 day', current_timestamp - interval '5 days', :'eventID', 'attendance-canceled', :'releasedRefundUserID'),
    (null, current_timestamp - interval '5 days', :'eventID', 'confirmed', :'replacedRefundUserID'),
    (current_timestamp - interval '1 day', current_timestamp - interval '2 days', :'eventID', 'attendance-canceled', :'unstampedRefundUserID');

-- Ticket tier used by every offer, purchase and waitlist entry
select fx_event_ticket_type(:'ticketTypeID', :'eventID');

-- Admission offers: active organizer invitation, expired, canceled after an
-- expired one, and active but refunding
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values
    (:'offerID', 0, current_timestamp - interval '1 hour', 0, :'eventID', :'ticketTypeID', current_timestamp + interval '1 day', 'organizer_invitation', 'pending', 'General admission', :'offerUserID'),
    (:'expiredOfferID', 0, current_timestamp - interval '2 days', 0, :'eventID', :'ticketTypeID', current_timestamp - interval '1 day', 'waitlist', 'pending', 'General admission', :'expiredOfferUserID'),
    (:'canceledOfferID', 0, current_timestamp - interval '3 days', 0, :'eventID', :'ticketTypeID', current_timestamp - interval '2 days', 'waitlist', 'canceled', 'General admission', :'expiredOfferUserID'),
    (:'refundingOfferID', 0, current_timestamp - interval '1 hour', 0, :'eventID', :'ticketTypeID', current_timestamp + interval '1 day', 'approval', 'checkout_pending', 'General admission', :'refundingUserID');

-- Invitation requests: pending and rejected
insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by)
values
    (:'eventID', :'approvalUserID', 'pending', null, null),
    (:'eventID', :'approvalRejectedUserID', 'rejected', current_timestamp, :'confirmedUserID');

-- Waitlisted user
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'ticketTypeID', :'waitlistedUserID');

-- Purchases: completed with a pending refund request, completed with a
-- rejected refund request, refunded with an approved refund request, pending,
-- stale pending hold and one being refunded behind an offer
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (null, 0, 'USD', :'eventID', :'confirmedPurchaseID', :'ticketTypeID', null, 'completed', 'General admission', :'confirmedUserID'),
    (null, 0, 'USD', :'eventID', :'rejectedRefundPurchaseID', :'ticketTypeID', null, 'completed', 'General admission', :'rejectedRefundUserID'),
    (null, 0, 'USD', :'eventID', :'approvedRefundPurchaseID', :'ticketTypeID', null, 'refunded', 'General admission', :'approvedRefundUserID'),
    (null, 0, 'USD', :'eventID', :'pendingPurchaseID', :'ticketTypeID', current_timestamp + interval '10 minutes', 'pending', 'General admission', :'pendingPurchaseUserID'),
    (null, 0, 'USD', :'eventID', :'staleHoldPurchaseID', :'ticketTypeID', current_timestamp - interval '10 minutes', 'pending', 'General admission', :'registrationUserID'),
    (:'refundingOfferID', 0, 'USD', :'eventID', :'refundingPurchaseID', :'ticketTypeID', null, 'refund-pending', 'General admission', :'refundingUserID');

-- Purchases with explicit timelines: refunded and later updated, refunded
-- before a revived attendance, refunded when the attendance was released,
-- completed replacement with a newer refunded purchase, and refunded without
-- a refund time
insert into event_purchase (
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    refunded_at,
    status,
    ticket_title,
    updated_at,
    user_id
) values
    (0, current_timestamp - interval '4 days', 'USD', :'eventID', :'newerAttendeeRefundPurchaseID', :'ticketTypeID', current_timestamp - interval '3 days', 'refunded', 'General admission', current_timestamp - interval '1 hour', :'newerAttendeeRefundUserID'),
    (0, current_timestamp - interval '5 days', 'USD', :'eventID', :'reattendedRefundPurchaseID', :'ticketTypeID', current_timestamp - interval '3 days', 'refunded', 'General admission', current_timestamp - interval '3 days', :'reattendedRefundUserID'),
    (0, current_timestamp - interval '5 days', 'USD', :'eventID', :'releasedRefundPurchaseID', :'ticketTypeID', current_timestamp - interval '1 day', 'refunded', 'General admission', current_timestamp - interval '1 day', :'releasedRefundUserID'),
    (0, current_timestamp - interval '5 days', 'USD', :'eventID', :'replacementPurchaseID', :'ticketTypeID', null, 'completed', 'General admission', current_timestamp - interval '5 days', :'replacedRefundUserID'),
    (0, current_timestamp - interval '2 days', 'USD', :'eventID', :'replacedRefundPurchaseID', :'ticketTypeID', current_timestamp - interval '1 day', 'refunded', 'General admission', current_timestamp - interval '1 day', :'replacedRefundUserID'),
    (0, current_timestamp - interval '4 days', 'USD', :'eventID', :'unstampedRefundPurchaseID', :'ticketTypeID', null, 'refunded', 'General admission', current_timestamp - interval '3 days', :'unstampedRefundUserID');

-- Refund requests: pending, rejected with a reason and approved with a note,
-- plus the approved requests of every purchase with an explicit timeline
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status,

    review_note,
    reviewed_at,
    reviewed_by_user_id
) values
    (:'confirmedPurchaseID', :'refundRequestID', :'confirmedUserID', 'pending', null, null, null),
    (:'rejectedRefundPurchaseID', :'rejectedRefundRequestID', :'rejectedRefundUserID', 'rejected', 'Outside the refund policy window', current_timestamp, :'confirmedUserID'),
    (:'approvedRefundPurchaseID', :'approvedRefundRequestID', :'approvedRefundUserID', 'approved', 'Approved as a courtesy', current_timestamp, :'confirmedUserID'),
    (:'newerAttendeeRefundPurchaseID', :'newerAttendeeRefundRequestID', :'newerAttendeeRefundUserID', 'approved', null, current_timestamp - interval '3 days', :'confirmedUserID'),
    (:'reattendedRefundPurchaseID', :'reattendedRefundRequestID', :'reattendedRefundUserID', 'approved', null, current_timestamp - interval '3 days', :'confirmedUserID'),
    (:'releasedRefundPurchaseID', :'releasedRefundRequestID', :'releasedRefundUserID', 'approved', null, current_timestamp - interval '1 day', :'confirmedUserID'),
    (:'replacedRefundPurchaseID', :'replacedRefundRequestID', :'replacedRefundUserID', 'approved', null, current_timestamp - interval '1 day', :'confirmedUserID'),
    (:'unstampedRefundPurchaseID', :'unstampedRefundRequestID', :'unstampedRefundUserID', 'approved', null, current_timestamp - interval '3 days', :'confirmedUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should always return exactly one row
select is(
    (select count(*) from event_user_enrollment(:'eventID', :'confirmedUserID')),
    1::bigint,
    'Should always return exactly one row'
);

-- Should fall back to the purchase update time when the refund time is missing
select results_eq(
    format(
        $$ select event_purchase_id, purchase_status, refund_request_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'unstampedRefundUserID'
    ),
    $$ values (null::uuid, null::text, null::text) $$,
    'Should fall back to the purchase update time when the refund time is missing'
);

-- Should ignore a refunded purchase when an attendee row was created after the refund
select results_eq(
    format(
        $$ select attendee_status, event_purchase_id, purchase_status, refund_request_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'newerAttendeeRefundUserID'
    ),
    $$ values ('attendance-canceled', null::uuid, null::text, null::text) $$,
    'Should ignore a refunded purchase when an attendee row was created after the refund'
);

-- Should ignore a refunded purchase when the user attends again without a new purchase
select results_eq(
    format(
        $$ select attendee_status, event_purchase_id, purchase_status, refund_rejection_reason, refund_request_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'reattendedRefundUserID'
    ),
    $$ values ('confirmed', null::uuid, null::text, null::text, null::text) $$,
    'Should ignore a refunded purchase when the user attends again without a new purchase'
);

-- Should ignore pending purchases whose hold expired
select results_eq(
    format(
        $$ select attendee_status, event_purchase_id, purchase_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'registrationUserID'
    ),
    $$ values ('registration-questions-pending', null::uuid, null::text) $$,
    'Should ignore pending purchases whose hold expired'
);

-- Should not report a rejection reason for a refund request that was not rejected
select results_eq(
    format(
        $$ select event_purchase_id, purchase_status, refund_rejection_reason, refund_request_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'approvedRefundUserID'
    ),
    format(
        $$ values (%L::uuid, 'refunded', null::text, 'approved') $$,
        :'approvedRefundPurchaseID'
    ),
    'Should not report a rejection reason for a refund request that was not rejected'
);

-- Should not treat an offer being refunded as active
select results_eq(
    format(
        $$ select admission_offer_id, event_purchase_id, purchase_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'refundingUserID'
    ),
    format($$ values (null::uuid, %L::uuid, 'refund-pending') $$, :'refundingPurchaseID'),
    'Should not treat an offer being refunded as active'
);

-- Should report a refunded purchase whose refund released the attendance
select results_eq(
    format(
        $$ select attendee_status, event_purchase_id, purchase_status, refund_request_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'releasedRefundUserID'
    ),
    format(
        $$ values ('attendance-canceled', %L::uuid, 'refunded', 'approved') $$,
        :'releasedRefundPurchaseID'
    ),
    'Should report a refunded purchase whose refund released the attendance'
);

-- Should report an unexpired pending purchase
select results_eq(
    format(
        $$ select event_purchase_id, purchase_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'pendingPurchaseUserID'
    ),
    format($$ values (%L::uuid, 'pending') $$, :'pendingPurchaseID'),
    'Should report an unexpired pending purchase'
);

-- Should report confirmed attendance with its purchase and refund request
select results_eq(
    format(
        $$ select attendee_checked_in, attendee_manually_invited, attendee_status, event_purchase_id, purchase_status, refund_rejection_reason, refund_request_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'confirmedUserID'
    ),
    format(
        $$ values (true, true, 'confirmed', %L::uuid, 'completed', null::text, 'pending') $$,
        :'confirmedPurchaseID'
    ),
    'Should report confirmed attendance with its purchase and refund request'
);

-- Should report declined invitations
select results_eq(
    format(
        $$ select attendee_manually_invited, attendee_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'declinedUserID'
    ),
    $$ values (true, 'invitation-rejected') $$,
    'Should report declined invitations'
);

-- Should report pending invitation requests
select is(
    (select invitation_request_status from event_user_enrollment(:'eventID', :'approvalUserID')),
    'pending',
    'Should report pending invitation requests'
);

-- Should report pending invitations
select results_eq(
    format(
        $$ select attendee_manually_invited, attendee_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'invitedUserID'
    ),
    $$ values (true, 'invitation-pending') $$,
    'Should report pending invitations'
);

-- Should report rejected invitation requests
select is(
    (select invitation_request_status from event_user_enrollment(:'eventID', :'approvalRejectedUserID')),
    'rejected',
    'Should report rejected invitation requests'
);

-- Should report the active admission offer
select results_eq(
    format(
        $$ select admission_offer_event_ticket_type_id, admission_offer_id, admission_offer_source, latest_offer_expired from event_user_enrollment(%L, %L) $$,
        :'eventID', :'offerUserID'
    ),
    format(
        $$ values (%L::uuid, %L::uuid, 'organizer_invitation', false) $$,
        :'ticketTypeID', :'offerID'
    ),
    'Should report the active admission offer'
);

-- Should report the latest lapsed offer as expired
select results_eq(
    format(
        $$ select admission_offer_id, latest_offer_expired from event_user_enrollment(%L, %L) $$,
        :'eventID', :'expiredOfferUserID'
    ),
    $$ values (null::uuid, true) $$,
    'Should report the latest lapsed offer as expired'
);

-- Should report the seat-holding purchase over a newer refund while the seat is held
select results_eq(
    format(
        $$ select attendee_status, event_purchase_id, purchase_status, refund_request_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'replacedRefundUserID'
    ),
    format(
        $$ values ('confirmed', %L::uuid, 'completed', null::text) $$,
        :'replacementPurchaseID'
    ),
    'Should report the seat-holding purchase over a newer refund while the seat is held'
);

-- Should report waitlisted users
select is(
    (select waitlisted from event_user_enrollment(:'eventID', :'waitlistedUserID')),
    true,
    'Should report waitlisted users'
);

-- Should return no facts for unknown users
select results_eq(
    format(
        $$ select admission_offer_event_ticket_type_id, admission_offer_id, admission_offer_source, attendee_checked_in, attendee_manually_invited, attendee_status, event_purchase_id, invitation_request_status, latest_offer_expired, purchase_status, refund_rejection_reason, refund_request_status, waitlisted from event_user_enrollment(%L, %L) $$,
        :'eventID', :'strangerUserID'
    ),
    $$ values (null::uuid, null::uuid, null::text, false, false, null::text, null::uuid, null::text, false, null::text, null::text, null::text, false) $$,
    'Should return no facts for unknown users'
);

-- Should return the reason of a rejected refund request
select results_eq(
    format(
        $$ select attendee_status, event_purchase_id, refund_rejection_reason, refund_request_status from event_user_enrollment(%L, %L) $$,
        :'eventID', :'rejectedRefundUserID'
    ),
    format(
        $$ values ('confirmed', %L::uuid, 'Outside the refund policy window', 'rejected') $$,
        :'rejectedRefundPurchaseID'
    ),
    'Should return the reason of a rejected refund request'
);

-- Should scope facts to the requested event
select results_eq(
    format(
        $$ select attendee_checked_in, attendee_status, event_purchase_id, purchase_status, refund_request_status from event_user_enrollment(%L, %L) $$,
        :'otherEventID', :'confirmedUserID'
    ),
    $$ values (false, 'invitation-pending', null::uuid, null::text, null::text) $$,
    'Should scope facts to the requested event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
