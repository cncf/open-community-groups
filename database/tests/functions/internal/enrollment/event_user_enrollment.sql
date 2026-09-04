-- Tests resolving a user's enrollment state for an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvalRejectedUserID 'f20a0000-0000-0000-0000-000000000001'
\set approvalUserID 'f20a0000-0000-0000-0000-000000000002'
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
\set offerID 'f20a0000-0000-0000-0000-00000000000f'
\set offerUserID 'f20a0000-0000-0000-0000-000000000010'
\set pendingPurchaseID 'f20a0000-0000-0000-0000-000000000011'
\set pendingPurchaseUserID 'f20a0000-0000-0000-0000-000000000012'
\set refundRequestID 'f20a0000-0000-0000-0000-000000000013'
\set refundingOfferID 'f20a0000-0000-0000-0000-000000000014'
\set refundingPurchaseID 'f20a0000-0000-0000-0000-000000000015'
\set refundingUserID 'f20a0000-0000-0000-0000-000000000016'
\set registrationUserID 'f20a0000-0000-0000-0000-000000000017'
\set staleHoldPurchaseID 'f20a0000-0000-0000-0000-000000000018'
\set strangerUserID 'f20a0000-0000-0000-0000-000000000019'
\set ticketTypeID 'f20a0000-0000-0000-0000-00000000001a'
\set waitlistedUserID 'f20a0000-0000-0000-0000-00000000001b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group, event, ticket type and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_event_ticket_type(:'ticketTypeID', :'eventID');
select fx_user(:'approvalRejectedUserID');
select fx_user(:'approvalUserID');
select fx_user(:'confirmedUserID');
select fx_user(:'declinedUserID');
select fx_user(:'expiredOfferUserID');
select fx_user(:'invitedUserID');
select fx_user(:'offerUserID');
select fx_user(:'pendingPurchaseUserID');
select fx_user(:'refundingUserID');
select fx_user(:'registrationUserID');
select fx_user(:'strangerUserID');
select fx_user(:'waitlistedUserID');

-- Attendee rows: confirmed and checked in, registration pending, invited and declined
insert into event_attendee (event_id, user_id, checked_in, manually_invited, status)
values
    (:'eventID', :'confirmedUserID', true, true, 'confirmed'),
    (:'eventID', :'registrationUserID', false, false, 'registration-questions-pending'),
    (:'eventID', :'invitedUserID', false, true, 'invitation-pending'),
    (:'eventID', :'declinedUserID', false, true, 'invitation-rejected');

-- Purchases: completed with a refund request, pending, stale pending hold and
-- one being refunded behind an offer
insert into event_purchase (
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
    (0, 'USD', :'eventID', :'confirmedPurchaseID', :'ticketTypeID', null, 'completed', 'General admission', :'confirmedUserID'),
    (0, 'USD', :'eventID', :'pendingPurchaseID', :'ticketTypeID', current_timestamp + interval '10 minutes', 'pending', 'General admission', :'pendingPurchaseUserID'),
    (0, 'USD', :'eventID', :'staleHoldPurchaseID', :'ticketTypeID', current_timestamp - interval '10 minutes', 'pending', 'General admission', :'registrationUserID');

-- Refund request on the completed purchase
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status
) values (
    :'confirmedPurchaseID',
    :'refundRequestID',
    :'confirmedUserID',
    'pending'
);

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

-- Purchase under refund linked to the refunding offer
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'refundingOfferID',
    0,
    'USD',
    :'eventID',
    :'refundingPurchaseID',
    :'ticketTypeID',
    'refund-pending',
    'General admission',
    :'refundingUserID'
);

-- Invitation requests: pending and rejected
insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by)
values
    (:'eventID', :'approvalUserID', 'pending', null, null),
    (:'eventID', :'approvalRejectedUserID', 'rejected', current_timestamp, :'confirmedUserID');

-- Waitlisted user
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'ticketTypeID', :'waitlistedUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report confirmed attendance with its purchase and refund request
select results_eq(
    format(
        $$ select attendee_checked_in, attendee_manually_invited, attendee_status, event_purchase_id, purchase_status, refund_request_status, state from event_user_enrollment(%L, %L) $$,
        :'eventID', :'confirmedUserID'
    ),
    format(
        $$ values (true, true, 'confirmed', %L::uuid, 'completed', 'pending', 'confirmed') $$,
        :'confirmedPurchaseID'
    ),
    'Should report confirmed attendance with its purchase and refund request'
);

-- Should report an unexpired pending purchase as payment pending
select results_eq(
    format(
        $$ select event_purchase_id, purchase_status, purchase_hold_expires_at > current_timestamp, state from event_user_enrollment(%L, %L) $$,
        :'eventID', :'pendingPurchaseUserID'
    ),
    format($$ values (%L::uuid, 'pending', true, 'payment-pending') $$, :'pendingPurchaseID'),
    'Should report an unexpired pending purchase as payment pending'
);

-- Should ignore pending purchases whose hold expired
select results_eq(
    format(
        $$ select event_purchase_id, attendee_status, state from event_user_enrollment(%L, %L) $$,
        :'eventID', :'registrationUserID'
    ),
    $$ values (null::uuid, 'registration-questions-pending', 'registration-pending') $$,
    'Should ignore pending purchases whose hold expired'
);

-- Should report the active admission offer
select results_eq(
    format(
        $$ select admission_offer_id, admission_offer_event_ticket_type_id, admission_offer_source, admission_offer_status, admission_offer_expires_at > current_timestamp, latest_offer_expired, state from event_user_enrollment(%L, %L) $$,
        :'eventID', :'offerUserID'
    ),
    format(
        $$ values (%L::uuid, %L::uuid, 'organizer_invitation', 'pending', true, false, 'offer-active') $$,
        :'offerID', :'ticketTypeID'
    ),
    'Should report the active admission offer'
);

-- Should not treat an offer being refunded as active
select results_eq(
    format(
        $$ select admission_offer_id, event_purchase_id, purchase_status, state from event_user_enrollment(%L, %L) $$,
        :'eventID', :'refundingUserID'
    ),
    format($$ values (null::uuid, %L::uuid, 'refund-pending', 'none') $$, :'refundingPurchaseID'),
    'Should not treat an offer being refunded as active'
);

-- Should report the latest lapsed offer as expired
select results_eq(
    format(
        $$ select admission_offer_id, latest_offer_expired, state from event_user_enrollment(%L, %L) $$,
        :'eventID', :'expiredOfferUserID'
    ),
    $$ values (null::uuid, true, 'offer-expired') $$,
    'Should report the latest lapsed offer as expired'
);

-- Should report pending invitations
select is(
    (select state from event_user_enrollment(:'eventID', :'invitedUserID')),
    'invitation-pending',
    'Should report pending invitations'
);

-- Should report declined invitations
select is(
    (select state from event_user_enrollment(:'eventID', :'declinedUserID')),
    'invitation-declined',
    'Should report declined invitations'
);

-- Should report pending invitation requests
select results_eq(
    format(
        $$ select invitation_request_status, state from event_user_enrollment(%L, %L) $$,
        :'eventID', :'approvalUserID'
    ),
    $$ values ('pending', 'approval-pending') $$,
    'Should report pending invitation requests'
);

-- Should report rejected invitation requests
select results_eq(
    format(
        $$ select invitation_request_status, state from event_user_enrollment(%L, %L) $$,
        :'eventID', :'approvalRejectedUserID'
    ),
    $$ values ('rejected', 'approval-rejected') $$,
    'Should report rejected invitation requests'
);

-- Should report waitlisted users
select results_eq(
    format(
        $$ select waitlisted, state from event_user_enrollment(%L, %L) $$,
        :'eventID', :'waitlistedUserID'
    ),
    $$ values (true, 'waitlisted') $$,
    'Should report waitlisted users'
);

-- Should return one row with no state for unknown users
select results_eq(
    format(
        $$ select attendee_checked_in, attendee_manually_invited, attendee_status, admission_offer_id, event_purchase_id, latest_offer_expired, waitlisted, state from event_user_enrollment(%L, %L) $$,
        :'eventID', :'strangerUserID'
    ),
    $$ values (false, false, null::text, null::uuid, null::uuid, false, false, 'none') $$,
    'Should return one row with no state for unknown users'
);

-- Should always return exactly one row
select is(
    (select count(*) from event_user_enrollment(:'eventID', :'confirmedUserID')),
    1::bigint,
    'Should always return exactly one row'
);

-- Should scope facts to the requested event
select is(
    (select state from event_user_enrollment(:'ticketTypeID', :'confirmedUserID')),
    'none',
    'Should scope facts to the requested event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
