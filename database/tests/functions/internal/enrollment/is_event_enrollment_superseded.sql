-- Tests whether a user's enrollment moved past a stale offer of a given source.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedRequestUserID 'f3070000-0000-0000-0000-000000000001'
\set attendanceCanceledUserID 'f3070000-0000-0000-0000-000000000002'
\set communityID 'f3070000-0000-0000-0000-000000000003'
\set completedLinkedOfferID 'f3070000-0000-0000-0000-000000000004'
\set completedPurchaseID 'f3070000-0000-0000-0000-000000000005'
\set completedPurchaseUserID 'f3070000-0000-0000-0000-000000000006'
\set confirmedUserID 'f3070000-0000-0000-0000-000000000007'
\set equalOtherSourceOfferID 'f3070000-0000-0000-0000-000000000008'
\set equalOtherSourceUserID 'f3070000-0000-0000-0000-000000000009'
\set eventCategoryID 'f3070000-0000-0000-0000-00000000000a'
\set eventID 'f3070000-0000-0000-0000-00000000000b'
\set expiredPurchaseID 'f3070000-0000-0000-0000-00000000000c'
\set expiredPurchaseUserID 'f3070000-0000-0000-0000-00000000000d'
\set groupCategoryID 'f3070000-0000-0000-0000-00000000000e'
\set groupID 'f3070000-0000-0000-0000-00000000000f'
\set invitationCanceledUserID 'f3070000-0000-0000-0000-000000000010'
\set invitationPendingUserID 'f3070000-0000-0000-0000-000000000011'
\set invitationRejectedUserID 'f3070000-0000-0000-0000-000000000012'
\set lapsedHoldPurchaseID 'f3070000-0000-0000-0000-000000000013'
\set lapsedHoldUserID 'f3070000-0000-0000-0000-000000000014'
\set linkedCheckoutOfferID 'f3070000-0000-0000-0000-000000000015'
\set linkedPendingPurchaseID 'f3070000-0000-0000-0000-000000000016'
\set linkedPendingUserID 'f3070000-0000-0000-0000-000000000017'
\set liveHoldPurchaseID 'f3070000-0000-0000-0000-000000000018'
\set liveHoldUserID 'f3070000-0000-0000-0000-000000000019'
\set newerCanceledOfferID 'f3070000-0000-0000-0000-00000000001a'
\set newerCanceledUserID 'f3070000-0000-0000-0000-00000000001b'
\set newerPendingOfferID 'f3070000-0000-0000-0000-00000000001c'
\set newerPendingUserID 'f3070000-0000-0000-0000-00000000001d'
\set newerSameSourceOfferID 'f3070000-0000-0000-0000-00000000001e'
\set newerSameSourceUserID 'f3070000-0000-0000-0000-00000000001f'
\set nullAnchorOfferID 'f3070000-0000-0000-0000-000000000020'
\set nullAnchorUserID 'f3070000-0000-0000-0000-000000000021'
\set olderOtherSourceOfferID 'f3070000-0000-0000-0000-000000000022'
\set olderOtherSourceUserID 'f3070000-0000-0000-0000-000000000023'
\set otherEventID 'f3070000-0000-0000-0000-000000000024'
\set otherEventUserID 'f3070000-0000-0000-0000-000000000025'
\set pendingRequestUserID 'f3070000-0000-0000-0000-000000000026'
\set questionsPendingUserID 'f3070000-0000-0000-0000-000000000027'
\set refundPendingPurchaseID 'f3070000-0000-0000-0000-000000000028'
\set refundPendingUserID 'f3070000-0000-0000-0000-000000000029'
\set refundRecoveryPurchaseID 'f3070000-0000-0000-0000-00000000002a'
\set refundRecoveryUserID 'f3070000-0000-0000-0000-00000000002b'
\set refundRequestedPurchaseID 'f3070000-0000-0000-0000-00000000002c'
\set refundRequestedUserID 'f3070000-0000-0000-0000-00000000002d'
\set refundedPurchaseID 'f3070000-0000-0000-0000-00000000002e'
\set refundedPurchaseUserID 'f3070000-0000-0000-0000-00000000002f'
\set rejectedRequestUserID 'f3070000-0000-0000-0000-000000000030'
\set reviewerUserID 'f3070000-0000-0000-0000-000000000031'
\set revivedAttendeeUserID 'f3070000-0000-0000-0000-000000000032'
\set strangerUserID 'f3070000-0000-0000-0000-000000000033'
\set ticketTypeID 'f3070000-0000-0000-0000-000000000034'
\set waitingUserID 'f3070000-0000-0000-0000-000000000035'

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
select fx_user(:'completedPurchaseUserID');
select fx_user(:'confirmedUserID');
select fx_user(:'equalOtherSourceUserID');
select fx_user(:'expiredPurchaseUserID');
select fx_user(:'invitationCanceledUserID');
select fx_user(:'invitationPendingUserID');
select fx_user(:'invitationRejectedUserID');
select fx_user(:'lapsedHoldUserID');
select fx_user(:'linkedPendingUserID');
select fx_user(:'liveHoldUserID');
select fx_user(:'newerCanceledUserID');
select fx_user(:'newerPendingUserID');
select fx_user(:'newerSameSourceUserID');
select fx_user(:'nullAnchorUserID');
select fx_user(:'olderOtherSourceUserID');
select fx_user(:'otherEventUserID');
select fx_user(:'pendingRequestUserID');
select fx_user(:'questionsPendingUserID');
select fx_user(:'refundPendingUserID');
select fx_user(:'refundRecoveryUserID');
select fx_user(:'refundRequestedUserID');
select fx_user(:'refundedPurchaseUserID');
select fx_user(:'rejectedRequestUserID');
select fx_user(:'reviewerUserID');
select fx_user(:'revivedAttendeeUserID');
select fx_user(:'strangerUserID');
select fx_user(:'waitingUserID');

-- Offers issued around the anchor: same source newer, other source older, equal and newer
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values
    (:'newerSameSourceOfferID', '2024-01-02 00:00:00+00', :'eventID', :'ticketTypeID', '2024-01-03 00:00:00+00', 'waitlist', 'expired', :'newerSameSourceUserID'),
    (:'olderOtherSourceOfferID', '2023-12-31 00:00:00+00', :'eventID', :'ticketTypeID', '2024-01-01 00:00:00+00', 'organizer_invitation', 'expired', :'olderOtherSourceUserID'),
    (:'equalOtherSourceOfferID', '2024-01-01 00:00:00+00', :'eventID', :'ticketTypeID', '2024-01-02 00:00:00+00', 'organizer_invitation', 'expired', :'equalOtherSourceUserID'),
    (:'newerCanceledOfferID', '2024-01-02 00:00:00+00', :'eventID', :'ticketTypeID', '2024-01-03 00:00:00+00', 'organizer_invitation', 'canceled', :'newerCanceledUserID'),
    (:'newerPendingOfferID', '2024-01-02 00:00:00+00', :'eventID', :'ticketTypeID', '2099-01-01 00:00:00+00', 'organizer_invitation', 'pending', :'newerPendingUserID'),
    (:'nullAnchorOfferID', '2024-01-02 00:00:00+00', :'eventID', :'ticketTypeID', '2024-01-03 00:00:00+00', 'organizer_invitation', 'canceled', :'nullAnchorUserID');

-- Same-source offers claimed by the linked purchases
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
    (:'linkedCheckoutOfferID', 0, '2024-01-02 00:00:00+00', 0, :'eventID', :'ticketTypeID', '2099-01-01 00:00:00+00', 'waitlist', 'checkout_pending', 'General admission', :'linkedPendingUserID'),
    (:'completedLinkedOfferID', 0, '2024-01-02 00:00:00+00', 0, :'eventID', :'ticketTypeID', '2024-01-03 00:00:00+00', 'waitlist', 'completed', 'General admission', :'completedPurchaseUserID');

-- Attendee rows in every canceled and active state, including a revived row older than the anchor
insert into event_attendee (created_at, event_id, status, user_id)
values
    ('2024-01-02 00:00:00+00', :'eventID', 'invitation-canceled', :'invitationCanceledUserID'),
    ('2024-01-02 00:00:00+00', :'eventID', 'invitation-rejected', :'invitationRejectedUserID'),
    ('2024-01-02 00:00:00+00', :'eventID', 'confirmed', :'confirmedUserID'),
    ('2024-01-02 00:00:00+00', :'eventID', 'invitation-pending', :'invitationPendingUserID'),
    ('2024-01-02 00:00:00+00', :'eventID', 'registration-questions-pending', :'questionsPendingUserID'),
    ('2023-12-01 00:00:00+00', :'eventID', 'confirmed', :'revivedAttendeeUserID'),
    ('2024-01-02 00:00:00+00', :'otherEventID', 'confirmed', :'otherEventUserID');

-- Attendee who canceled their attendance after the anchor
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    created_at,
    event_id,
    status,
    user_id
) values (
    '2024-01-03 00:00:00+00',
    :'attendanceCanceledUserID',
    '2024-01-02 00:00:00+00',
    :'eventID',
    'attendance-canceled',
    :'attendanceCanceledUserID'
);

-- Invitation requests: pending, accepted and rejected
insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by)
values
    (:'eventID', :'pendingRequestUserID', 'pending', null, null),
    (:'eventID', :'acceptedRequestUserID', 'accepted', '2024-01-02 00:00:00+00', :'reviewerUserID'),
    (:'eventID', :'rejectedRequestUserID', 'rejected', '2024-01-02 00:00:00+00', :'reviewerUserID');

-- Direct purchases in every status, with live and lapsed pending holds
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
    (0, 'USD', :'eventID', :'expiredPurchaseID', :'ticketTypeID', '2024-01-02 00:00:00+00', 'expired', 'General admission', :'expiredPurchaseUserID'),
    (0, 'USD', :'eventID', :'refundedPurchaseID', :'ticketTypeID', null, 'refunded', 'General admission', :'refundedPurchaseUserID'),
    (0, 'USD', :'eventID', :'liveHoldPurchaseID', :'ticketTypeID', current_timestamp + interval '10 minutes', 'pending', 'General admission', :'liveHoldUserID'),
    (0, 'USD', :'eventID', :'lapsedHoldPurchaseID', :'ticketTypeID', current_timestamp - interval '10 minutes', 'pending', 'General admission', :'lapsedHoldUserID'),
    (0, 'USD', :'eventID', :'refundPendingPurchaseID', :'ticketTypeID', null, 'refund-pending', 'General admission', :'refundPendingUserID'),
    (0, 'USD', :'eventID', :'refundRecoveryPurchaseID', :'ticketTypeID', null, 'refund-recovery-pending', 'General admission', :'refundRecoveryUserID'),
    (0, 'USD', :'eventID', :'refundRequestedPurchaseID', :'ticketTypeID', null, 'refund-requested', 'General admission', :'refundRequestedUserID');

-- Purchases linked to the same-source offers they claim
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
    (:'linkedCheckoutOfferID', 0, 'USD', :'eventID', :'linkedPendingPurchaseID', :'ticketTypeID', current_timestamp + interval '10 minutes', 'pending', 'General admission', :'linkedPendingUserID'),
    (:'completedLinkedOfferID', 0, 'USD', :'eventID', :'completedPurchaseID', :'ticketTypeID', null, 'completed', 'General admission', :'completedPurchaseUserID');

-- Waiting-list entry that rejoined the queue
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'ticketTypeID', :'waitingUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore a newer offer from the same source
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'newerSameSourceUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    false,
    'Should ignore a newer offer from the same source'
);

-- Should ignore an offer from another source issued at the anchor time
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'equalOtherSourceUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    false,
    'Should ignore an offer from another source issued at the anchor time'
);

-- Should ignore an older offer from another source
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'olderOtherSourceUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    false,
    'Should ignore an older offer from another source'
);

-- Should ignore canceled or declined attendee rows
select results_eq(
    format(
        $$
        select is_event_enrollment_superseded(%L::uuid, user_id, 'waitlist', '2024-01-01 00:00:00+00'::timestamptz)
        from unnest(array[%L::uuid, %L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'attendanceCanceledUserID', :'invitationCanceledUserID', :'invitationRejectedUserID'
    ),
    $$ values (false), (false), (false) $$,
    'Should ignore canceled or declined attendee rows'
);

-- Should ignore enrollment in another event
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'otherEventUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    false,
    'Should ignore enrollment in another event'
);

-- Should ignore expired and refunded purchases
select results_eq(
    format(
        $$
        select is_event_enrollment_superseded(%L::uuid, user_id, 'waitlist', '2024-01-01 00:00:00+00'::timestamptz)
        from unnest(array[%L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'expiredPurchaseUserID', :'refundedPurchaseUserID'
    ),
    $$ values (false), (false) $$,
    'Should ignore expired and refunded purchases'
);

-- Should ignore reviewed invitation requests
select results_eq(
    format(
        $$
        select is_event_enrollment_superseded(%L::uuid, user_id, 'waitlist', '2024-01-01 00:00:00+00'::timestamptz)
        from unnest(array[%L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'acceptedRequestUserID', :'rejectedRequestUserID'
    ),
    $$ values (false), (false) $$,
    'Should ignore reviewed invitation requests'
);

-- Should report a newer canceled offer from another source as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'newerCanceledUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a newer canceled offer from another source as superseding'
);

-- Should report a newer pending offer from another source as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'newerPendingUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a newer pending offer from another source as superseding'
);

-- Should report a pending invitation request as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'pendingRequestUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a pending invitation request as superseding'
);

-- Should report a pending purchase as superseding regardless of hold deadline
select results_eq(
    format(
        $$
        select is_event_enrollment_superseded(%L::uuid, user_id, 'waitlist', '2024-01-01 00:00:00+00'::timestamptz)
        from unnest(array[%L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'liveHoldUserID', :'lapsedHoldUserID'
    ),
    $$ values (true), (true) $$,
    'Should report a pending purchase as superseding regardless of hold deadline'
);

-- Should report a pending purchase linked to a same-source offer as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'linkedPendingUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a pending purchase linked to a same-source offer as superseding'
);

-- Should report a revived attendee row older than the anchor as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'revivedAttendeeUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a revived attendee row older than the anchor as superseding'
);

-- Should report a user without other enrollment as not superseded
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'strangerUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    false,
    'Should report a user without other enrollment as not superseded'
);

-- Should report a waiting-list entry as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'waitingUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a waiting-list entry as superseding'
);

-- Should report active attendee states as superseding
select results_eq(
    format(
        $$
        select is_event_enrollment_superseded(%L::uuid, user_id, 'waitlist', '2024-01-01 00:00:00+00'::timestamptz)
        from unnest(array[%L::uuid, %L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'confirmedUserID', :'invitationPendingUserID', :'questionsPendingUserID'
    ),
    $$ values (true), (true), (true) $$,
    'Should report active attendee states as superseding'
);

-- Should report every seat-holding purchase status as superseding
select results_eq(
    format(
        $$
        select is_event_enrollment_superseded(%L::uuid, user_id, 'waitlist', '2024-01-01 00:00:00+00'::timestamptz)
        from unnest(array[%L::uuid, %L::uuid, %L::uuid, %L::uuid]) as user_id
        $$,
        :'eventID', :'completedPurchaseUserID', :'refundPendingUserID', :'refundRecoveryUserID', :'refundRequestedUserID'
    ),
    $$ values (true), (true), (true), (true) $$,
    'Should report every seat-holding purchase status as superseding'
);

-- Should skip offer recency when the anchor is null
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'nullAnchorUserID'::uuid,
        'waitlist',
        null::timestamptz
    ),
    false,
    'Should skip offer recency when the anchor is null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
