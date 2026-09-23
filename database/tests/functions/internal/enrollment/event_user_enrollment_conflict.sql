-- Tests reporting the enrollment a user already holds that excludes a new admission offer.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedRequestUserID 'f30a0000-0000-0000-0000-000000000001'
\set attendanceCanceledUserID 'f30a0000-0000-0000-0000-000000000002'
\set attendancePrecedencePurchaseID 'f30a0000-0000-0000-0000-000000000003'
\set attendancePrecedenceUserID 'f30a0000-0000-0000-0000-000000000004'
\set communityID 'f30a0000-0000-0000-0000-000000000005'
\set completedPurchaseID 'f30a0000-0000-0000-0000-000000000006'
\set completedPurchaseUserID 'f30a0000-0000-0000-0000-000000000007'
\set confirmedUserID 'f30a0000-0000-0000-0000-000000000008'
\set eventCategoryID 'f30a0000-0000-0000-0000-000000000009'
\set eventID 'f30a0000-0000-0000-0000-00000000000a'
\set expiredPurchaseID 'f30a0000-0000-0000-0000-00000000000b'
\set expiredPurchaseUserID 'f30a0000-0000-0000-0000-00000000000c'
\set groupCategoryID 'f30a0000-0000-0000-0000-00000000000d'
\set groupID 'f30a0000-0000-0000-0000-00000000000e'
\set invitationCanceledUserID 'f30a0000-0000-0000-0000-00000000000f'
\set invitationPendingUserID 'f30a0000-0000-0000-0000-000000000010'
\set invitationRejectedUserID 'f30a0000-0000-0000-0000-000000000011'
\set lapsedHoldPurchaseID 'f30a0000-0000-0000-0000-000000000012'
\set lapsedHoldUserID 'f30a0000-0000-0000-0000-000000000013'
\set linkedOfferID 'f30a0000-0000-0000-0000-000000000014'
\set linkedPurchaseID 'f30a0000-0000-0000-0000-000000000015'
\set linkedPurchaseUserID 'f30a0000-0000-0000-0000-000000000016'
\set liveHoldPurchaseID 'f30a0000-0000-0000-0000-000000000017'
\set liveHoldUserID 'f30a0000-0000-0000-0000-000000000018'
\set otherEventID 'f30a0000-0000-0000-0000-000000000019'
\set otherEventUserID 'f30a0000-0000-0000-0000-00000000001a'
\set pendingRequestUserID 'f30a0000-0000-0000-0000-00000000001b'
\set questionsPendingUserID 'f30a0000-0000-0000-0000-00000000001c'
\set refundPendingPurchaseID 'f30a0000-0000-0000-0000-00000000001d'
\set refundPendingUserID 'f30a0000-0000-0000-0000-00000000001e'
\set refundRecoveryPurchaseID 'f30a0000-0000-0000-0000-00000000001f'
\set refundRecoveryUserID 'f30a0000-0000-0000-0000-000000000020'
\set refundRequestedPurchaseID 'f30a0000-0000-0000-0000-000000000021'
\set refundRequestedUserID 'f30a0000-0000-0000-0000-000000000022'
\set refundedPurchaseID 'f30a0000-0000-0000-0000-000000000023'
\set refundedPurchaseUserID 'f30a0000-0000-0000-0000-000000000024'
\set rejectedRequestUserID 'f30a0000-0000-0000-0000-000000000025'
\set requestPrecedencePurchaseID 'f30a0000-0000-0000-0000-000000000026'
\set requestPrecedenceUserID 'f30a0000-0000-0000-0000-000000000027'
\set reviewerUserID 'f30a0000-0000-0000-0000-000000000028'
\set strangerUserID 'f30a0000-0000-0000-0000-000000000029'
\set ticketTypeID 'f30a0000-0000-0000-0000-00000000002a'
\set waitingUserID 'f30a0000-0000-0000-0000-00000000002b'
\set waitlistPrecedencePurchaseID 'f30a0000-0000-0000-0000-00000000002c'
\set waitlistPrecedenceUserID 'f30a0000-0000-0000-0000-00000000002d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group, events and ticket type
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');
select fx_event_ticket_type(:'ticketTypeID', :'eventID');

-- One user per scenario plus the reviewer of the request decisions
select fx_user(:'acceptedRequestUserID');
select fx_user(:'attendanceCanceledUserID');
select fx_user(:'attendancePrecedenceUserID');
select fx_user(:'completedPurchaseUserID');
select fx_user(:'confirmedUserID');
select fx_user(:'expiredPurchaseUserID');
select fx_user(:'invitationCanceledUserID');
select fx_user(:'invitationPendingUserID');
select fx_user(:'invitationRejectedUserID');
select fx_user(:'lapsedHoldUserID');
select fx_user(:'linkedPurchaseUserID');
select fx_user(:'liveHoldUserID');
select fx_user(:'otherEventUserID');
select fx_user(:'pendingRequestUserID');
select fx_user(:'questionsPendingUserID');
select fx_user(:'refundPendingUserID');
select fx_user(:'refundRecoveryUserID');
select fx_user(:'refundRequestedUserID');
select fx_user(:'refundedPurchaseUserID');
select fx_user(:'rejectedRequestUserID');
select fx_user(:'requestPrecedenceUserID');
select fx_user(:'reviewerUserID');
select fx_user(:'strangerUserID');
select fx_user(:'waitingUserID');
select fx_user(:'waitlistPrecedenceUserID');

-- Offer being claimed by the purchase linked to it
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'linkedOfferID',
    0,
    0,
    :'eventID',
    :'ticketTypeID',
    '2099-01-01 00:00:00+00',
    'organizer_invitation',
    'checkout_pending',
    'General admission',
    :'linkedPurchaseUserID'
);

-- Attendee rows in every canceled and active state, in this event and another one
insert into event_attendee (event_id, status, user_id)
values
    (:'eventID', 'invitation-canceled', :'invitationCanceledUserID'),
    (:'eventID', 'invitation-rejected', :'invitationRejectedUserID'),
    (:'eventID', 'confirmed', :'confirmedUserID'),
    (:'eventID', 'invitation-pending', :'invitationPendingUserID'),
    (:'eventID', 'registration-questions-pending', :'questionsPendingUserID'),
    (:'eventID', 'confirmed', :'attendancePrecedenceUserID'),
    (:'otherEventID', 'confirmed', :'otherEventUserID');

-- Attendee who canceled their attendance
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values (
    current_timestamp,
    :'attendanceCanceledUserID',
    :'eventID',
    'attendance-canceled',
    :'attendanceCanceledUserID'
);

-- Invitation requests: pending, accepted and rejected, plus pending ones beneath stronger enrollment
insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by)
values
    (:'eventID', :'pendingRequestUserID', 'pending', null, null),
    (:'eventID', :'acceptedRequestUserID', 'accepted', current_timestamp, :'reviewerUserID'),
    (:'eventID', :'rejectedRequestUserID', 'rejected', current_timestamp, :'reviewerUserID'),
    (:'eventID', :'attendancePrecedenceUserID', 'pending', null, null),
    (:'eventID', :'requestPrecedenceUserID', 'pending', null, null),
    (:'eventID', :'waitlistPrecedenceUserID', 'pending', null, null);

-- Direct purchases in every status, with live and lapsed pending holds, plus ones beneath stronger enrollment
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
    (0, 'USD', :'eventID', :'expiredPurchaseID', :'ticketTypeID', current_timestamp - interval '10 minutes', 'expired', 'General admission', :'expiredPurchaseUserID'),
    (0, 'USD', :'eventID', :'refundedPurchaseID', :'ticketTypeID', null, 'refunded', 'General admission', :'refundedPurchaseUserID'),
    (0, 'USD', :'eventID', :'liveHoldPurchaseID', :'ticketTypeID', current_timestamp + interval '10 minutes', 'pending', 'General admission', :'liveHoldUserID'),
    (0, 'USD', :'eventID', :'lapsedHoldPurchaseID', :'ticketTypeID', current_timestamp - interval '10 minutes', 'pending', 'General admission', :'lapsedHoldUserID'),
    (0, 'USD', :'eventID', :'completedPurchaseID', :'ticketTypeID', null, 'completed', 'General admission', :'completedPurchaseUserID'),
    (0, 'USD', :'eventID', :'refundPendingPurchaseID', :'ticketTypeID', null, 'refund-pending', 'General admission', :'refundPendingUserID'),
    (0, 'USD', :'eventID', :'refundRecoveryPurchaseID', :'ticketTypeID', null, 'refund-recovery-pending', 'General admission', :'refundRecoveryUserID'),
    (0, 'USD', :'eventID', :'refundRequestedPurchaseID', :'ticketTypeID', null, 'refund-requested', 'General admission', :'refundRequestedUserID'),
    (0, 'USD', :'eventID', :'attendancePrecedencePurchaseID', :'ticketTypeID', null, 'completed', 'General admission', :'attendancePrecedenceUserID'),
    (0, 'USD', :'eventID', :'requestPrecedencePurchaseID', :'ticketTypeID', null, 'completed', 'General admission', :'requestPrecedenceUserID'),
    (0, 'USD', :'eventID', :'waitlistPrecedencePurchaseID', :'ticketTypeID', current_timestamp + interval '10 minutes', 'pending', 'General admission', :'waitlistPrecedenceUserID');

-- Pending purchase claiming the linked offer
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
) values (
    :'linkedOfferID',
    0,
    'USD',
    :'eventID',
    :'linkedPurchaseID',
    :'ticketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'linkedPurchaseUserID'
);

-- Waiting-list entries, one beneath a pending request and purchase
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values
    (:'eventID', :'ticketTypeID', :'waitingUserID'),
    (:'eventID', :'ticketTypeID', :'waitlistPrecedenceUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore canceled or declined attendee rows
select results_eq(
    format(
        $$
        select event_user_enrollment_conflict(%L::uuid, user_id, null)
        from unnest(array[%L::uuid, %L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'attendanceCanceledUserID', :'invitationCanceledUserID', :'invitationRejectedUserID'
    ),
    $$ values (null::text), (null::text), (null::text) $$,
    'Should ignore canceled or declined attendee rows'
);

-- Should ignore enrollment in another event
select is(
    event_user_enrollment_conflict(:'eventID'::uuid, :'otherEventUserID'::uuid, null),
    null::text,
    'Should ignore enrollment in another event'
);

-- Should ignore expired and refunded purchases
select results_eq(
    format(
        $$
        select event_user_enrollment_conflict(%L::uuid, user_id, null)
        from unnest(array[%L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'expiredPurchaseUserID', :'refundedPurchaseUserID'
    ),
    $$ values (null::text), (null::text) $$,
    'Should ignore expired and refunded purchases'
);

-- Should ignore reviewed invitation requests
select results_eq(
    format(
        $$
        select event_user_enrollment_conflict(%L::uuid, user_id, null)
        from unnest(array[%L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'acceptedRequestUserID', :'rejectedRequestUserID'
    ),
    $$ values (null::text), (null::text) $$,
    'Should ignore reviewed invitation requests'
);

-- Should ignore the purchase linked to the given offer
select is(
    event_user_enrollment_conflict(:'eventID'::uuid, :'linkedPurchaseUserID'::uuid, :'linkedOfferID'::uuid),
    null::text,
    'Should ignore the purchase linked to the given offer'
);

-- Should report a pending invitation request as request
select is(
    event_user_enrollment_conflict(:'eventID'::uuid, :'pendingRequestUserID'::uuid, null),
    'request',
    'Should report a pending invitation request as request'
);

-- Should report a pending purchase as purchase regardless of hold deadline
select results_eq(
    format(
        $$
        select event_user_enrollment_conflict(%L::uuid, user_id, null)
        from unnest(array[%L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'liveHoldUserID', :'lapsedHoldUserID'
    ),
    $$ values ('purchase'::text), ('purchase'::text) $$,
    'Should report a pending purchase as purchase regardless of hold deadline'
);

-- Should report a waiting-list entry as waitlist
select is(
    event_user_enrollment_conflict(:'eventID'::uuid, :'waitingUserID'::uuid, null),
    'waitlist',
    'Should report a waiting-list entry as waitlist'
);

-- Should report active attendee states as attendance
select results_eq(
    format(
        $$
        select event_user_enrollment_conflict(%L::uuid, user_id, null)
        from unnest(array[%L::uuid, %L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'confirmedUserID', :'invitationPendingUserID', :'questionsPendingUserID'
    ),
    $$ values ('attendance'::text), ('attendance'::text), ('attendance'::text) $$,
    'Should report active attendee states as attendance'
);

-- Should report every seat-holding purchase status as purchase
select results_eq(
    format(
        $$
        select event_user_enrollment_conflict(%L::uuid, user_id, null)
        from unnest(array[%L::uuid, %L::uuid, %L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'completedPurchaseUserID', :'refundPendingUserID', :'refundRecoveryUserID', :'refundRequestedUserID'
    ),
    $$ values ('purchase'::text), ('purchase'::text), ('purchase'::text), ('purchase'::text) $$,
    'Should report every seat-holding purchase status as purchase'
);

-- Should report no conflict for a user without enrollment
select is(
    event_user_enrollment_conflict(:'eventID'::uuid, :'strangerUserID'::uuid, null),
    null::text,
    'Should report no conflict for a user without enrollment'
);

-- Should report the linked purchase when no offer is excluded
select is(
    event_user_enrollment_conflict(:'eventID'::uuid, :'linkedPurchaseUserID'::uuid, null),
    'purchase',
    'Should report the linked purchase when no offer is excluded'
);

-- Should report the strongest enrollment first
select results_eq(
    format(
        $$
        select event_user_enrollment_conflict(%L::uuid, user_id, null)
        from unnest(array[%L::uuid, %L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'attendancePrecedenceUserID', :'waitlistPrecedenceUserID', :'requestPrecedenceUserID'
    ),
    $$ values ('attendance'::text), ('waitlist'::text), ('request'::text) $$,
    'Should report the strongest enrollment first'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
