-- Tests current enrollment counts of an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ea050000-0000-0000-0000-000000000001'
\set eventCategoryID 'ea050000-0000-0000-0000-000000000002'
\set eventEmptyID 'ea050000-0000-0000-0000-000000000003'
\set eventID 'ea050000-0000-0000-0000-000000000004'
\set eventPathsID 'ea050000-0000-0000-0000-00000000001b'
\set groupCategoryID 'ea050000-0000-0000-0000-000000000005'
\set groupID 'ea050000-0000-0000-0000-000000000006'
\set offerPathApprovalID 'ea050000-0000-0000-0000-00000000001c'
\set offerPathOrganizerID 'ea050000-0000-0000-0000-00000000001d'
\set offerPathWaitlistID 'ea050000-0000-0000-0000-00000000001e'
\set reviewerID 'ea050000-0000-0000-0000-000000000007'
\set ticketTypeID 'ea050000-0000-0000-0000-000000000008'
\set ticketTypePathsID 'ea050000-0000-0000-0000-00000000001f'
\set userCanceledID 'ea050000-0000-0000-0000-000000000009'
\set userCheckedInID 'ea050000-0000-0000-0000-00000000000a'
\set userConfirmedID 'ea050000-0000-0000-0000-00000000000b'
\set userInvitationPendingID 'ea050000-0000-0000-0000-00000000000c'
\set userInvitationRejectedID 'ea050000-0000-0000-0000-00000000000d'
\set userOfferActiveID 'ea050000-0000-0000-0000-00000000000e'
\set userOfferCanceledID 'ea050000-0000-0000-0000-00000000000f'
\set userOfferCheckoutDeadlineID 'ea050000-0000-0000-0000-000000000010'
\set userOfferCompletedID 'ea050000-0000-0000-0000-000000000011'
\set userOfferDeadlineID 'ea050000-0000-0000-0000-000000000012'
\set userOfferDeclinedID 'ea050000-0000-0000-0000-000000000013'
\set userOfferExpiredID 'ea050000-0000-0000-0000-000000000014'
\set userPathApprovalID 'ea050000-0000-0000-0000-000000000020'
\set userPathDirectID 'ea050000-0000-0000-0000-000000000021'
\set userPathManualID 'ea050000-0000-0000-0000-000000000022'
\set userPathOrganizerID 'ea050000-0000-0000-0000-000000000023'
\set userPathUnknownID 'ea050000-0000-0000-0000-000000000024'
\set userPathWaitlistID 'ea050000-0000-0000-0000-000000000025'
\set userQuestionsPendingID 'ea050000-0000-0000-0000-000000000015'
\set userRequestAcceptedID 'ea050000-0000-0000-0000-000000000016'
\set userRequestPendingID 'ea050000-0000-0000-0000-000000000017'
\set userRequestRejectedID 'ea050000-0000-0000-0000-000000000018'
\set userWaitlist1ID 'ea050000-0000-0000-0000-000000000019'
\set userWaitlist2ID 'ea050000-0000-0000-0000-00000000001a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'reviewerID');
select fx_user(:'userCanceledID');
select fx_user(:'userCheckedInID');
select fx_user(:'userConfirmedID');
select fx_user(:'userInvitationPendingID');
select fx_user(:'userInvitationRejectedID');
select fx_user(:'userOfferActiveID');
select fx_user(:'userOfferCanceledID');
select fx_user(:'userOfferCheckoutDeadlineID');
select fx_user(:'userOfferCompletedID');
select fx_user(:'userOfferDeadlineID');
select fx_user(:'userOfferDeclinedID');
select fx_user(:'userOfferExpiredID');
select fx_user(:'userPathApprovalID');
select fx_user(:'userPathDirectID');
select fx_user(:'userPathManualID');
select fx_user(:'userPathOrganizerID');
select fx_user(:'userPathUnknownID');
select fx_user(:'userPathWaitlistID');
select fx_user(:'userQuestionsPendingID');
select fx_user(:'userRequestAcceptedID');
select fx_user(:'userRequestPendingID');
select fx_user(:'userRequestRejectedID');
select fx_user(:'userWaitlist1ID');
select fx_user(:'userWaitlist2ID');

-- Event whose enrollment is counted
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event without enrollment rows
select fx_event(:'eventEmptyID', :'groupID', :'eventCategoryID');

-- Event whose registrations are attributed to their admission paths
select fx_event(:'eventPathsID', :'groupID', :'eventCategoryID');

-- Ticket type referenced by offers and waitlist entries
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('title', 'General'));

-- Ticket type of the purchases holding the attributed seats
select fx_event_ticket_type(:'ticketTypePathsID', :'eventPathsID', jsonb_build_object('title', 'General'));

-- Admission offers covering every source and outcome
insert into admission_offer (
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
) values
    (current_timestamp - interval '2 days', :'eventID', :'ticketTypeID', current_timestamp - interval '1 hour', 'approval', 'checkout_pending', :'userOfferCheckoutDeadlineID', 0, 0, 'General'),
    (current_timestamp - interval '2 days', :'eventID', :'ticketTypeID', current_timestamp - interval '1 day', 'approval', 'completed', :'userOfferCompletedID', 0, 0, 'General'),
    (current_timestamp - interval '2 days', :'eventID', :'ticketTypeID', current_timestamp - interval '1 day', 'organizer_invitation', 'canceled', :'userOfferCanceledID', null, null, null),
    (current_timestamp - interval '2 days', :'eventID', :'ticketTypeID', current_timestamp - interval '1 day', 'organizer_invitation', 'declined', :'userOfferDeclinedID', null, null, null),
    (current_timestamp - interval '2 days', :'eventID', :'ticketTypeID', current_timestamp - interval '1 day', 'organizer_invitation', 'expired', :'userOfferExpiredID', null, null, null),
    (current_timestamp - interval '1 hour', :'eventID', :'ticketTypeID', current_timestamp + interval '1 day', 'waitlist', 'pending', :'userOfferActiveID', null, null, null),
    (current_timestamp - interval '2 days', :'eventID', :'ticketTypeID', current_timestamp - interval '1 day', 'waitlist', 'pending', :'userOfferDeadlineID', null, null, null);

-- Completed admission offers claimed by the purchases of the attributed seats
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
) values
    (:'offerPathApprovalID', current_timestamp - interval '2 days', :'eventPathsID', :'ticketTypePathsID', current_timestamp - interval '1 day', 'approval', 'completed', :'userPathApprovalID', 0, 0, 'General'),
    (:'offerPathOrganizerID', current_timestamp - interval '2 days', :'eventPathsID', :'ticketTypePathsID', current_timestamp - interval '1 day', 'organizer_invitation', 'completed', :'userPathOrganizerID', 0, 0, 'General'),
    (:'offerPathWaitlistID', current_timestamp - interval '2 days', :'eventPathsID', :'ticketTypePathsID', current_timestamp - interval '1 day', 'waitlist', 'completed', :'userPathWaitlistID', 0, 0, 'General');

-- Attendees covering every attendee status
insert into event_attendee (
    event_id,
    user_id,
    checked_in,
    status,

    attendance_canceled_at,
    checked_in_at
) values
    (:'eventID', :'userCanceledID', false, 'attendance-canceled', current_timestamp, null),
    (:'eventID', :'userCheckedInID', true, 'confirmed', null, current_timestamp),
    (:'eventID', :'userConfirmedID', false, 'confirmed', null, null),
    (:'eventID', :'userInvitationPendingID', false, 'invitation-pending', null, null),
    (:'eventID', :'userInvitationRejectedID', false, 'invitation-rejected', null, null),
    (:'eventID', :'userQuestionsPendingID', false, 'registration-questions-pending', null, null);

-- Confirmed attendees admitted through every registration path
insert into event_attendee (
    event_id,
    user_id,
    manually_invited,
    status
) values
    (:'eventPathsID', :'userPathApprovalID', false, 'confirmed'),
    (:'eventPathsID', :'userPathDirectID', false, 'confirmed'),
    (:'eventPathsID', :'userPathManualID', true, 'confirmed'),
    (:'eventPathsID', :'userPathOrganizerID', true, 'confirmed'),
    (:'eventPathsID', :'userPathUnknownID', false, 'confirmed'),
    (:'eventPathsID', :'userPathWaitlistID', false, 'confirmed');

-- Invitation requests covering every review status
insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by) values
    (:'eventID', :'userRequestAcceptedID', 'accepted', current_timestamp, :'reviewerID'),
    (:'eventID', :'userRequestPendingID', 'pending', null, null),
    (:'eventID', :'userRequestRejectedID', 'rejected', current_timestamp, :'reviewerID');

-- Purchases holding the attributed seats, plus an earlier refunded direct purchase
insert into event_purchase (
    amount_minor,
    created_at,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    admission_offer_id,
    completed_at
) values
    (0, current_timestamp - interval '1 day', :'eventPathsID', :'ticketTypePathsID', 'completed', 'General', :'userPathApprovalID', :'offerPathApprovalID', current_timestamp - interval '1 day'),
    (0, current_timestamp - interval '1 day', :'eventPathsID', :'ticketTypePathsID', 'completed', 'General', :'userPathDirectID', null, current_timestamp - interval '1 day'),
    (0, current_timestamp - interval '1 day', :'eventPathsID', :'ticketTypePathsID', 'completed', 'General', :'userPathOrganizerID', :'offerPathOrganizerID', current_timestamp - interval '1 day'),
    (0, current_timestamp - interval '3 days', :'eventPathsID', :'ticketTypePathsID', 'refunded', 'General', :'userPathWaitlistID', null, current_timestamp - interval '3 days'),
    (0, current_timestamp - interval '1 day', :'eventPathsID', :'ticketTypePathsID', 'completed', 'General', :'userPathWaitlistID', :'offerPathWaitlistID', current_timestamp - interval '1 day');

-- Waitlist entries
insert into event_waitlist (event_id, user_id, event_ticket_type_id) values
    (:'eventID', :'userWaitlist1ID', :'ticketTypeID'),
    (:'eventID', :'userWaitlist2ID', :'ticketTypeID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count admission offers by source and outcome
select is(
    (select stats_event_enrollment(e)::jsonb->'admission_offers' from event e where e.event_id = :'eventID'),
    '[
        {"count": 1, "outcome": "completed", "source": "approval"},
        {"count": 1, "outcome": "deadline-passed", "source": "approval"},
        {"count": 1, "outcome": "canceled", "source": "organizer_invitation"},
        {"count": 1, "outcome": "declined", "source": "organizer_invitation"},
        {"count": 1, "outcome": "expired", "source": "organizer_invitation"},
        {"count": 1, "outcome": "active", "source": "waitlist"},
        {"count": 1, "outcome": "deadline-passed", "source": "waitlist"}
    ]'::jsonb,
    'Should count admission offers by source and outcome'
);

-- Should attribute registrations to the path that admitted them
select is(
    (select stats_event_enrollment(e)::jsonb->'registrations_by_path' from event e where e.event_id = :'eventPathsID'),
    '{
        "approval": 1,
        "direct": 1,
        "organizer_invitation": 2,
        "unknown": 1,
        "waitlist": 1
    }'::jsonb,
    'Should attribute registrations to the path that admitted them'
);

-- Should count attendees, invitation requests and the waitlist by status
select is(
    (
        select stats_event_enrollment(e)::jsonb - 'admission_offers' - 'registrations_by_path'
        from event e
        where e.event_id = :'eventID'
    ),
    '{
        "cancellations": 1,
        "checked_in": 1,
        "invitation_requests": {"accepted": 1, "pending": 1, "rejected": 1},
        "registrations": 2,
        "waitlist": 2
    }'::jsonb,
    'Should count attendees, invitation requests and the waitlist by status'
);

-- Should return zero counts for events without enrollment rows
select is(
    (select stats_event_enrollment(e)::jsonb from event e where e.event_id = :'eventEmptyID'),
    '{
        "admission_offers": [],
        "cancellations": 0,
        "checked_in": 0,
        "invitation_requests": {"accepted": 0, "pending": 0, "rejected": 0},
        "registrations": 0,
        "registrations_by_path": {
            "approval": 0,
            "direct": 0,
            "organizer_invitation": 0,
            "unknown": 0,
            "waitlist": 0
        },
        "waitlist": 0
    }'::jsonb,
    'Should return zero counts for events without enrollment rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
