-- Tests accepting event invitation requests.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(55);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a010000-0000-0000-0000-000000000001'
\set communityID '3a010000-0000-0000-0000-000000000002'
\set eventApprovalDisabledID '3a010000-0000-0000-0000-000000000003'
\set eventAttendeeConflictID '3a010000-0000-0000-0000-000000000004'
\set eventAttendanceCanceledID '3a010000-0000-0000-0000-000000000025'
\set eventCategoryID '3a010000-0000-0000-0000-000000000005'
\set eventExpiredReservationID '3a010000-0000-0000-0000-00000000004c'
\set expiredReservationOfferOneID '3a010000-0000-0000-0000-00000000004d'
\set expiredReservationOfferTwoID '3a010000-0000-0000-0000-00000000004e'
\set expiredReservationOfferUserOneID '3a010000-0000-0000-0000-00000000004f'
\set expiredReservationOfferUserTwoID '3a010000-0000-0000-0000-000000000050'
\set expiredReservationRequesterID '3a010000-0000-0000-0000-000000000051'
\set expiredReservationWaitlistUserID '3a010000-0000-0000-0000-000000000052'
\set eventFullID '3a010000-0000-0000-0000-000000000006'
\set eventID '3a010000-0000-0000-0000-000000000007'
\set eventInProgressApprovalID '3a010000-0000-0000-0000-000000000053'
\set eventInactiveGroupID '3a010000-0000-0000-0000-000000000008'
\set eventPastID '3a010000-0000-0000-0000-000000000009'
\set eventPendingInvitationID '3a010000-0000-0000-0000-000000000010'
\set eventPaidNoRecipientApprovalID '3a010000-0000-0000-0000-000000000038'
\set eventPrivateTicketApprovalID '3a010000-0000-0000-0000-000000000027'
\set eventPublicTicketApprovalID '3a010000-0000-0000-0000-000000000028'
\set eventQuestionsApprovalID '3a010000-0000-0000-0000-000000000011'
\set eventQueuePriorityID '3a010000-0000-0000-0000-00000000002e'
\set eventRegistrationOpenUntilStartID '3a010000-0000-0000-0000-000000000023'
\set eventReissueOfferBlockID '3a010000-0000-0000-0000-000000000039'
\set eventReissuePurchaseBlockID '3a010000-0000-0000-0000-00000000003a'
\set eventTicketSoldOutID '3a010000-0000-0000-0000-00000000002f'
\set eventUnpublishedID '3a010000-0000-0000-0000-000000000012'
\set eventUnavailableTicketApprovalID '3a010000-0000-0000-0000-00000000003b'
\set groupCategoryID '3a010000-0000-0000-0000-000000000013'
\set groupID '3a010000-0000-0000-0000-000000000014'
\set inactiveGroupID '3a010000-0000-0000-0000-000000000015'
\set inProgressPriceWindowID '3a010000-0000-0000-0000-000000000054'
\set inProgressRequesterID '3a010000-0000-0000-0000-000000000055'
\set inProgressTicketTypeID '3a010000-0000-0000-0000-000000000056'
\set questionsAcceptedRequestUserID '3a010000-0000-0000-0000-000000000016'
\set queuePriorityPriceWindowID '3a010000-0000-0000-0000-000000000030'
\set queuePriorityRequesterID '3a010000-0000-0000-0000-000000000031'
\set queuePriorityTicketTypeID '3a010000-0000-0000-0000-000000000032'
\set queuePriorityWaitlistUserID '3a010000-0000-0000-0000-000000000033'
\set registrationQuestionID '3a010000-0000-0000-0000-000000000017'
\set requesterID '3a010000-0000-0000-0000-000000000018'
\set requester2ID '3a010000-0000-0000-0000-000000000019'
\set requester3ID '3a010000-0000-0000-0000-000000000020'
\set requester4ID '3a010000-0000-0000-0000-000000000021'
\set requester5ID '3a010000-0000-0000-0000-000000000022'
\set requester6ID '3a010000-0000-0000-0000-000000000024'
\set requester7ID '3a010000-0000-0000-0000-000000000026'
\set privateTicketPriceWindowID '3a010000-0000-0000-0000-000000000029'
\set privateTicketTypeID '3a010000-0000-0000-0000-00000000002a'
\set paidTicketPriceWindowID '3a010000-0000-0000-0000-00000000003c'
\set paidTicketTypeID '3a010000-0000-0000-0000-00000000003d'
\set publicAlternateTicketPriceWindowID '3a010000-0000-0000-0000-00000000003e'
\set publicAlternateTicketTypeID '3a010000-0000-0000-0000-00000000003f'
\set publicGenericTicketPriceWindowID '3a010000-0000-0000-0000-000000000040'
\set publicGenericTicketTypeID '3a010000-0000-0000-0000-000000000041'
\set publicTicketPriceWindowID '3a010000-0000-0000-0000-00000000002b'
\set publicTicketTypeID '3a010000-0000-0000-0000-00000000002c'
\set reissueOfferBlockPriceWindowID '3a010000-0000-0000-0000-000000000042'
\set reissueOfferBlockTicketTypeID '3a010000-0000-0000-0000-000000000043'
\set reissuePurchaseBlockPriceWindowID '3a010000-0000-0000-0000-000000000044'
\set reissuePurchaseBlockTicketTypeID '3a010000-0000-0000-0000-000000000045'
\set siteID '3a010000-0000-0000-0000-00000000002d'
\set soldOutOccupantID '3a010000-0000-0000-0000-000000000034'
\set soldOutPriceWindowID '3a010000-0000-0000-0000-000000000035'
\set soldOutRequesterID '3a010000-0000-0000-0000-000000000036'
\set soldOutTicketTypeID '3a010000-0000-0000-0000-000000000037'
\set requester8ID '3a010000-0000-0000-0000-000000000046'
\set requester9ID '3a010000-0000-0000-0000-000000000047'
\set requester10ID '3a010000-0000-0000-0000-000000000048'
\set requester11ID '3a010000-0000-0000-0000-000000000049'
\set requester12ID '3a010000-0000-0000-0000-00000000004a'
\set unavailableTicketTypeID '3a010000-0000-0000-0000-00000000004b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into site (description, site_id, theme, title)
values (
    'Invitation request approval site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Invitation Request Approval Site'
);

insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
)
values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'actorID', 'h', 'actor@test.com', 'actor'),
    (:'inProgressRequesterID', 'h', 'in-progress@test.com', 'in-progress'),
    (:'requesterID', 'h', 'requester@test.com', 'requester'),
    (:'requester2ID', 'h', 'requester2@test.com', 'requester2'),
    (:'requester3ID', 'h', 'requester3@test.com', 'requester3'),
    (:'requester4ID', 'h', 'requester4@test.com', 'requester4'),
    (:'requester5ID', 'h', 'requester5@test.com', 'requester5'),
    (:'requester6ID', 'h', 'requester6@test.com', 'requester6'),
    (:'requester7ID', 'h', 'requester7@test.com', 'requester7'),
    (:'requester8ID', 'h', 'requester8@test.com', 'requester8'),
    (:'requester9ID', 'h', 'requester9@test.com', 'requester9'),
    (:'requester10ID', 'h', 'requester10@test.com', 'requester10'),
    (:'requester11ID', 'h', 'requester11@test.com', 'requester11'),
    (:'requester12ID', 'h', 'requester12@test.com', 'requester12'),
    (:'questionsAcceptedRequestUserID', 'h', 'rq-accepted-request@test.com', 'rq-accepted-request'),
    (:'queuePriorityRequesterID', 'h', 'queue-priority-requester@test.com', 'queue-priority-requester'),
    (:'queuePriorityWaitlistUserID', 'h', 'queue-priority-waitlist@test.com', 'queue-priority-waitlist'),
    (:'soldOutOccupantID', 'h', 'sold-out-occupant@test.com', 'sold-out-occupant'),
    (:'soldOutRequesterID', 'h', 'sold-out-requester@test.com', 'sold-out-requester');

-- Users used by expired RSVP reservation reconciliation acceptance
insert into "user" (user_id, auth_hash, email, username)
values
    (
        :'expiredReservationOfferUserOneID',
        'h',
        'expired-reservation-offer-one@test.com',
        'expired-reservation-offer-one'
    ),
    (
        :'expiredReservationOfferUserTwoID',
        'h',
        'expired-reservation-offer-two@test.com',
        'expired-reservation-offer-two'
    ),
    (
        :'expiredReservationRequesterID',
        'h',
        'expired-reservation-requester@test.com',
        'expired-reservation-requester'
    ),
    (
        :'expiredReservationWaitlistUserID',
        'h',
        'expired-reservation-waitlist@test.com',
        'expired-reservation-waitlist'
    );

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug, active)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Group', 'group', true),
    (
        :'inactiveGroupID',
        :'communityID',
        :'groupCategoryID',
        'Inactive Group',
        'inactive-group',
        false
    );

-- Events
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    capacity,
    attendee_approval_required,
    starts_at,
    ends_at,
    registration_starts_at
)
values
    (
        :'eventID',
        'Invite Event',
        'invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        2,
        true,
        null,
        null,
        null
    ),
    (
        :'eventAttendanceCanceledID',
        'Attendance Canceled Event',
        'attendance-canceled-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        null,
        null,
        null
    ),
    (
        :'eventFullID',
        'Full Invite Event',
        'full-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        1,
        true,
        null,
        null,
        null
    ),
    (
        :'eventUnpublishedID',
        'Unpublished Invite Event',
        'unpublished-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        null,
        true,
        null,
        null,
        null
    ),
    (
        :'eventInactiveGroupID',
        'Inactive Group Invite Event',
        'inactive-group-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'inactiveGroupID',
        true,
        null,
        true,
        null,
        null,
        null
    ),
    (
        :'eventApprovalDisabledID',
        'Approval Disabled Event',
        'approval-disabled-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        false,
        null,
        null,
        null
    ),
    (
        :'eventPastID',
        'Past Invite Event',
        'past-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        current_timestamp - interval '2 hours',
        current_timestamp - interval '1 hour',
        null
    ),
    (
        :'eventPendingInvitationID',
        'Pending Invitation Event',
        'pending-invitation-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        null,
        null,
        null
    ),
    (
        :'eventAttendeeConflictID',
        'Attendee Conflict Event',
        'attendee-conflict-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        null,
        null,
        null
    ),
    (
        :'eventRegistrationOpenUntilStartID',
        'Registration Open Until Start Event',
        'registration-open-until-start-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        current_timestamp - interval '1 hour',
        current_timestamp + interval '1 hour',
        current_timestamp - interval '2 hours'
    );

-- RSVP approval event whose expired reservations are swept before acceptance
insert into event (
    attendee_approval_required,
    capacity,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    true,
    2,
    'Expired reservation approval event',
    :'eventCategoryID',
    :'eventExpiredReservationID',
    'in-person',
    :'groupID',
    'Expired Reservation Approval',
    true,
    'expired-reservation-approval',
    current_timestamp + interval '1 day',
    'UTC'
);

-- Event with registration questions used to verify answer copying on accept
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    attendee_approval_required,
    starts_at,
    registration_questions
) values (
    :'eventQuestionsApprovalID',
    'Approval Questions Event',
    'approval-questions-event',
    'd',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    true,
    '2030-01-02 10:00:00+00',
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'registrationQuestionID'
    )::jsonb
);

-- Ticketed approval events for tier assignment and capacity conflict scenarios
insert into event (
    attendee_approval_required,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values
    (
        true,
        'Private ticket approval event',
        :'eventCategoryID',
        :'eventPrivateTicketApprovalID',
        'in-person',
        :'groupID',
        'Private Ticket Approval',
        true,
        'private-ticket-approval',
        current_timestamp + interval '1 day',
        'UTC'
    ),
    (
        true,
        'Public ticket approval event',
        :'eventCategoryID',
        :'eventPublicTicketApprovalID',
        'in-person',
        :'groupID',
        'Public Ticket Approval',
        true,
        'public-ticket-approval',
        current_timestamp + interval '1 day',
        'UTC'
    ),
    (
        true,
        'Queue priority ticket approval event',
        :'eventCategoryID',
        :'eventQueuePriorityID',
        'in-person',
        :'groupID',
        'Queue Priority Ticket Approval',
        true,
        'queue-priority-ticket-approval',
        current_timestamp + interval '1 day',
        'UTC'
    ),
    (
        true,
        'Sold out ticket approval event',
        :'eventCategoryID',
        :'eventTicketSoldOutID',
        'in-person',
        :'groupID',
        'Sold Out Ticket Approval',
        true,
        'sold-out-ticket-approval',
        current_timestamp + interval '1 day',
        'UTC'
    ),
    (
        true,
        'Unavailable ticket approval event',
        :'eventCategoryID',
        :'eventUnavailableTicketApprovalID',
        'in-person',
        :'groupID',
        'Unavailable Ticket Approval',
        true,
        'unavailable-ticket-approval',
        current_timestamp + interval '1 day',
        'UTC'
    ),
    (
        true,
        'Reissue offer blocker approval event',
        :'eventCategoryID',
        :'eventReissueOfferBlockID',
        'in-person',
        :'groupID',
        'Reissue Offer Blocker Approval',
        true,
        'reissue-offer-blocker-approval',
        current_timestamp + interval '1 day',
        'UTC'
    ),
    (
        true,
        'Reissue purchase blocker approval event',
        :'eventCategoryID',
        :'eventReissuePurchaseBlockID',
        'in-person',
        :'groupID',
        'Reissue Purchase Blocker Approval',
        true,
        'reissue-purchase-blocker-approval',
        current_timestamp + interval '1 day',
        'UTC'
    );

-- In-progress ticketed approval event with a pending request
insert into event (
    attendee_approval_required,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    registration_ends_at,
    registration_starts_at,
    slug,
    starts_at,
    timezone
) values (
    true,
    'In-progress ticket approval event',
    current_timestamp + interval '2 hours',
    :'eventCategoryID',
    :'eventInProgressApprovalID',
    'in-person',
    :'groupID',
    'In-Progress Ticket Approval',
    true,
    current_timestamp - interval '1 hour',
    current_timestamp - interval '2 hours',
    'in-progress-ticket-approval',
    current_timestamp - interval '1 hour',
    'UTC'
);

-- Paid ticket approval event with no payment recipient configured on the group
insert into event (
    attendee_approval_required,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    timezone
) values (
    true,
    'Paid ticket approval event',
    :'eventCategoryID',
    :'eventPaidNoRecipientApprovalID',
    'in-person',
    :'groupID',
    'Paid Ticket Approval',
    'USD',
    true,
    'paid-ticket-approval',
    current_timestamp + interval '1 day',
    'UTC'
);

-- Ticket tiers assigned or checked by the approval workflows
insert into event_ticket_type (
    active,
    availability,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values
    (
        true,
        'public',
        :'eventInProgressApprovalID',
        :'inProgressTicketTypeID',
        1,
        1,
        'In-progress admission'
    ),
    (
        true,
        'invitation_only',
        :'eventPrivateTicketApprovalID',
        :'privateTicketTypeID',
        1,
        1,
        'Private admission'
    ),
    (
        true,
        'public',
        :'eventPublicTicketApprovalID',
        :'publicAlternateTicketTypeID',
        2,
        2,
        'Alternate public admission'
    ),
    (
        true,
        'public',
        :'eventPrivateTicketApprovalID',
        :'publicGenericTicketTypeID',
        2,
        1,
        'Generic public admission'
    ),
    (
        true,
        'public',
        :'eventPublicTicketApprovalID',
        :'publicTicketTypeID',
        1,
        2,
        'Public admission'
    ),
    (
        true,
        'public',
        :'eventQueuePriorityID',
        :'queuePriorityTicketTypeID',
        1,
        1,
        'Queue priority admission'
    ),
    (
        true,
        'public',
        :'eventTicketSoldOutID',
        :'soldOutTicketTypeID',
        1,
        1,
        'Sold out admission'
    ),
    (
        false,
        'public',
        :'eventUnavailableTicketApprovalID',
        :'unavailableTicketTypeID',
        1,
        1,
        'Unavailable admission'
    ),
    (
        true,
        'public',
        :'eventPaidNoRecipientApprovalID',
        :'paidTicketTypeID',
        1,
        1,
        'Paid admission'
    ),
    (
        true,
        'public',
        :'eventReissueOfferBlockID',
        :'reissueOfferBlockTicketTypeID',
        1,
        1,
        'Reissue offer admission'
    ),
    (
        true,
        'public',
        :'eventReissuePurchaseBlockID',
        :'reissuePurchaseBlockTicketTypeID',
        1,
        1,
        'Reissue purchase admission'
    );

-- Current free prices for every ticket approval tier
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values
    (0, :'inProgressPriceWindowID', :'inProgressTicketTypeID'),
    (0, :'privateTicketPriceWindowID', :'privateTicketTypeID'),
    (2500, :'paidTicketPriceWindowID', :'paidTicketTypeID'),
    (0, :'publicAlternateTicketPriceWindowID', :'publicAlternateTicketTypeID'),
    (0, :'publicGenericTicketPriceWindowID', :'publicGenericTicketTypeID'),
    (0, :'publicTicketPriceWindowID', :'publicTicketTypeID'),
    (0, :'reissueOfferBlockPriceWindowID', :'reissueOfferBlockTicketTypeID'),
    (0, :'reissuePurchaseBlockPriceWindowID', :'reissuePurchaseBlockTicketTypeID'),
    (0, :'queuePriorityPriceWindowID', :'queuePriorityTicketTypeID'),
    (0, :'soldOutPriceWindowID', :'soldOutTicketTypeID');

-- Invitation requests
insert into event_invitation_request (event_id, event_ticket_type_id, user_id)
values
    (:'eventID', null, :'requesterID'),
    (:'eventID', null, :'requester2ID'),
    (:'eventFullID', null, :'requesterID'),
    (:'eventUnpublishedID', null, :'requesterID'),
    (:'eventInactiveGroupID', null, :'requesterID'),
    (:'eventApprovalDisabledID', null, :'requesterID'),
    (:'eventPastID', null, :'requesterID'),
    (:'eventPendingInvitationID', null, :'requester3ID'),
    (:'eventAttendeeConflictID', null, :'requester4ID'),
    (:'eventAttendeeConflictID', null, :'requester5ID'),
    (:'eventInProgressApprovalID', :'inProgressTicketTypeID', :'inProgressRequesterID'),
    (:'eventRegistrationOpenUntilStartID', null, :'requester6ID'),
    (:'eventAttendanceCanceledID', null, :'requester7ID'),
    (:'eventPrivateTicketApprovalID', null, :'requester3ID'),
    (:'eventPrivateTicketApprovalID', :'privateTicketTypeID', :'requester8ID'),
    (:'eventPublicTicketApprovalID', :'publicTicketTypeID', :'requester4ID'),
    (:'eventUnavailableTicketApprovalID', :'unavailableTicketTypeID', :'requester9ID'),
    (:'eventPaidNoRecipientApprovalID', :'paidTicketTypeID', :'requester10ID'),
    (:'eventQueuePriorityID', :'queuePriorityTicketTypeID', :'queuePriorityRequesterID'),
    (:'eventTicketSoldOutID', :'soldOutTicketTypeID', :'soldOutRequesterID');

-- Pending RSVP request accepted after expired reservations are reconciled
insert into event_invitation_request (event_id, event_ticket_type_id, user_id)
values (:'eventExpiredReservationID', null, :'expiredReservationRequesterID');

-- Accepted requests used to exercise ticket-offer reissue blockers
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    reviewed_at,
    reviewed_by,
    status,
    user_id
) values
    (
        :'eventReissueOfferBlockID',
        :'reissueOfferBlockTicketTypeID',
        current_timestamp,
        :'actorID',
        'accepted',
        :'requester11ID'
    ),
    (
        :'eventReissuePurchaseBlockID',
        :'reissuePurchaseBlockTicketTypeID',
        current_timestamp,
        :'actorID',
        'accepted',
        :'requester12ID'
    );

-- Active offer that blocks reissuing an accepted ticket request
insert into admission_offer (
    event_id,
    event_ticket_type_id,
    expires_at,
    organizer_user_id,
    source,
    status,
    user_id
) values (
    :'eventReissueOfferBlockID',
    :'reissueOfferBlockTicketTypeID',
    current_timestamp + interval '12 hours',
    :'actorID',
    'approval',
    'pending',
    :'requester11ID'
);

-- Active purchase that blocks reissuing an accepted ticket request
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    1000,
    'USD',
    :'eventReissuePurchaseBlockID',
    :'reissuePurchaseBlockTicketTypeID',
    'completed',
    'Reissue purchase admission',
    :'requester12ID'
);

-- Waitlist head that must receive the only queue-priority ticket
insert into event_waitlist (
    event_id,
    event_ticket_type_id,
    user_id
) values (
    :'eventQueuePriorityID',
    :'queuePriorityTicketTypeID',
    :'queuePriorityWaitlistUserID'
);

-- Expired RSVP offers that previously blocked capacity acceptance
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    expires_at,
    source,
    status,
    user_id
) values
    (
        :'expiredReservationOfferOneID',
        current_timestamp - interval '3 hours',
        :'eventExpiredReservationID',
        current_timestamp - interval '2 hours',
        'organizer_invitation',
        'pending',
        :'expiredReservationOfferUserOneID'
    ),
    (
        :'expiredReservationOfferTwoID',
        current_timestamp - interval '2 hours',
        :'eventExpiredReservationID',
        current_timestamp - interval '1 hour',
        'organizer_invitation',
        'pending',
        :'expiredReservationOfferUserTwoID'
    );

-- RSVP waitlist user promoted while expired reservations are swept
insert into event_waitlist (event_id, user_id)
values (:'eventExpiredReservationID', :'expiredReservationWaitlistUserID');

-- Active offer that occupies the only sold-out ticket
insert into admission_offer (
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'eventTicketSoldOutID',
    :'soldOutTicketTypeID',
    current_timestamp + interval '12 hours',
    'organizer_invitation',
    'pending',
    :'soldOutOccupantID'
);

-- Invitation request with registration answers copied when accepted
insert into event_invitation_request (event_id, user_id, registration_answers)
values (
    :'eventQuestionsApprovalID',
    :'questionsAcceptedRequestUserID',
    format(
        '{"answers": [{"question_id": "%s", "value": "Accepted request answer"}]}',
        :'registrationQuestionID'
    )::jsonb
);

-- Existing attendee that fills the second event
insert into event_attendee (event_id, user_id)
values (:'eventFullID', :'requester2ID');

-- Existing canceled manual invitation row for attendee upsert reuse
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'eventID', :'requester2ID', false, 'invitation-canceled');

-- Existing pending manual invitation row for attendee upsert reuse
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'eventPendingInvitationID', :'requester3ID', true, 'invitation-pending');

-- Existing attendee rows that block accepting their pending requests
insert into event_attendee (event_id, user_id, status)
values
    (:'eventAttendeeConflictID', :'requester4ID', 'confirmed'),
    (:'eventAttendeeConflictID', :'requester5ID', 'invitation-rejected');

-- Existing canceled attendance row reactivated by accepting a new request
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values (
    current_timestamp,
    :'requester7ID',
    :'eventAttendanceCanceledID',
    'attendance-canceled',
    :'requester7ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject changing the requested ticket type during approval
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L)',
        :'actorID',
        :'groupID',
        :'eventPublicTicketApprovalID',
        :'requester4ID',
        :'publicAlternateTicketTypeID',
        'stripe'
    ),
    'requested ticket type cannot be changed',
    'Should reject changing the requested ticket type during approval'
);

-- Should leave changed-ticket requests pending without an offer
select is(
    (
        select jsonb_build_object(
            'offer_count', (
                select count(*)::int
                from admission_offer ao
                where ao.event_id = :'eventPublicTicketApprovalID'::uuid
                and ao.user_id = :'requester4ID'::uuid
            ),
            'request_status', eir.status
        )
        from event_invitation_request eir
        where eir.event_id = :'eventPublicTicketApprovalID'::uuid
        and eir.user_id = :'requester4ID'::uuid
    ),
    '{"offer_count":0,"request_status":"pending"}'::jsonb,
    'Should leave changed-ticket requests pending without an offer'
);

-- Should reject generic requests without an invitation-only tier
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,%L)',
        :'actorID',
        :'groupID',
        :'eventPrivateTicketApprovalID',
        :'requester3ID',
        'stripe'
    ),
    'invitation-only ticket type is required',
    'Should reject generic requests without an invitation-only tier'
);

-- Should leave missing-tier generic requests pending without an offer
select is(
    (
        select jsonb_build_object(
            'offer_count', (
                select count(*)::int
                from admission_offer ao
                where ao.event_id = :'eventPrivateTicketApprovalID'::uuid
                and ao.user_id = :'requester3ID'::uuid
            ),
            'request_status', eir.status
        )
        from event_invitation_request eir
        where eir.event_id = :'eventPrivateTicketApprovalID'::uuid
        and eir.user_id = :'requester3ID'::uuid
    ),
    '{"offer_count":0,"request_status":"pending"}'::jsonb,
    'Should leave missing-tier generic requests pending without an offer'
);

-- Should reject unavailable requested ticket types
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,%L)',
        :'actorID',
        :'groupID',
        :'eventUnavailableTicketApprovalID',
        :'requester9ID',
        'stripe'
    ),
    'ticket type is not available',
    'Should reject unavailable requested ticket types'
);

-- Should leave unavailable-ticket requests pending without an offer
select is(
    (
        select jsonb_build_object(
            'offer_count', (
                select count(*)::int
                from admission_offer ao
                where ao.event_id = :'eventUnavailableTicketApprovalID'::uuid
                and ao.user_id = :'requester9ID'::uuid
            ),
            'request_status', eir.status
        )
        from event_invitation_request eir
        where eir.event_id = :'eventUnavailableTicketApprovalID'::uuid
        and eir.user_id = :'requester9ID'::uuid
    ),
    '{"offer_count":0,"request_status":"pending"}'::jsonb,
    'Should leave unavailable-ticket requests pending without an offer'
);

-- Should reject requested ticket types that are not public
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,%L)',
        :'actorID',
        :'groupID',
        :'eventPrivateTicketApprovalID',
        :'requester8ID',
        'stripe'
    ),
    'requested ticket type is not public',
    'Should reject requested ticket types that are not public'
);

-- Should leave private requested-ticket requests pending without an offer
select is(
    (
        select jsonb_build_object(
            'offer_count', (
                select count(*)::int
                from admission_offer ao
                where ao.event_id = :'eventPrivateTicketApprovalID'::uuid
                and ao.user_id = :'requester8ID'::uuid
            ),
            'request_status', eir.status
        )
        from event_invitation_request eir
        where eir.event_id = :'eventPrivateTicketApprovalID'::uuid
        and eir.user_id = :'requester8ID'::uuid
    ),
    '{"offer_count":0,"request_status":"pending"}'::jsonb,
    'Should leave private requested-ticket requests pending without an offer'
);

-- Should reject assigning a public tier to a generic request
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L)',
        :'actorID',
        :'groupID',
        :'eventPrivateTicketApprovalID',
        :'requester3ID',
        :'publicGenericTicketTypeID',
        'stripe'
    ),
    'generic requests require an invitation-only ticket type',
    'Should reject assigning a public tier to a generic request'
);

-- Should reject reissuing when an active offer already exists
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,%L)',
        :'actorID',
        :'groupID',
        :'eventReissueOfferBlockID',
        :'requester11ID',
        'stripe'
    ),
    'user already has an active admission offer for this event',
    'Should reject reissuing when an active offer already exists'
);

-- Should leave active-offer reissue requests accepted without a new offer
select is(
    (
        select jsonb_build_object(
            'offer_count', (
                select count(*)::int
                from admission_offer ao
                where ao.event_id = :'eventReissueOfferBlockID'::uuid
                and ao.user_id = :'requester11ID'::uuid
            ),
            'request_status', eir.status
        )
        from event_invitation_request eir
        where eir.event_id = :'eventReissueOfferBlockID'::uuid
        and eir.user_id = :'requester11ID'::uuid
    ),
    '{"offer_count":1,"request_status":"accepted"}'::jsonb,
    'Should leave active-offer reissue requests accepted without a new offer'
);

-- Should reject reissuing when an active purchase already exists
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,%L)',
        :'actorID',
        :'groupID',
        :'eventReissuePurchaseBlockID',
        :'requester12ID',
        'stripe'
    ),
    'user already has an active purchase for this event',
    'Should reject reissuing when an active purchase already exists'
);

-- Should leave active-purchase reissue requests accepted without an offer
select is(
    (
        select jsonb_build_object(
            'offer_count', (
                select count(*)::int
                from admission_offer ao
                where ao.event_id = :'eventReissuePurchaseBlockID'::uuid
                and ao.user_id = :'requester12ID'::uuid
            ),
            'purchase_count', (
                select count(*)::int
                from event_purchase ep
                where ep.event_id = :'eventReissuePurchaseBlockID'::uuid
                and ep.user_id = :'requester12ID'::uuid
            ),
            'request_status', eir.status
        )
        from event_invitation_request eir
        where eir.event_id = :'eventReissuePurchaseBlockID'::uuid
        and eir.user_id = :'requester12ID'::uuid
    ),
    '{"offer_count":0,"purchase_count":1,"request_status":"accepted"}'::jsonb,
    'Should leave active-purchase reissue requests accepted without an offer'
);

-- Should reject paid approval when the group payment recipient is missing
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,%L)',
        :'actorID',
        :'groupID',
        :'eventPaidNoRecipientApprovalID',
        :'requester10ID',
        'stripe'
    ),
    'paid-capable events require a payment recipient',
    'Should reject paid approval when the group payment recipient is missing'
);

-- Should leave paid-readiness failures pending without an offer
select is(
    (
        select jsonb_build_object(
            'offer_count', (
                select count(*)::int
                from admission_offer ao
                where ao.event_id = :'eventPaidNoRecipientApprovalID'::uuid
                and ao.user_id = :'requester10ID'::uuid
            ),
            'request_status', eir.status
        )
        from event_invitation_request eir
        where eir.event_id = :'eventPaidNoRecipientApprovalID'::uuid
        and eir.user_id = :'requester10ID'::uuid
    ),
    '{"offer_count":0,"request_status":"pending"}'::jsonb,
    'Should leave paid-readiness failures pending without an offer'
);

-- Should accept a request bound to its selected public ticket tier
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,%L)',
        :'actorID',
        :'groupID',
        :'eventPublicTicketApprovalID',
        :'requester4ID',
        'stripe'
    ),
    'Should accept a public-tier ticket request'
);

-- Should create a reserved public-tier offer without confirming attendance
select is(
    (
        select jsonb_build_object(
            'attendee_count', (
                select count(*)
                from event_attendee
                where event_id = :'eventPublicTicketApprovalID'::uuid
            ),
            'offer_status', ao.status,
            'request_status', eir.status,
            'ticket_type_id', ao.event_ticket_type_id
        )
        from event_invitation_request eir
        join admission_offer ao
            on ao.event_id = eir.event_id
            and ao.user_id = eir.user_id
        where eir.event_id = :'eventPublicTicketApprovalID'::uuid
        and eir.user_id = :'requester4ID'::uuid
    ),
    format(
        '{"attendee_count":0,"offer_status":"pending","request_status":"accepted","ticket_type_id":"%s"}',
        :'publicTicketTypeID'
    )::jsonb,
    'Should create the public-tier approval offer'
);

-- Should accept ticket requests while the event remains in progress
select is(
    accept_event_invitation_request(
        :'actorID',
        :'groupID',
        :'eventInProgressApprovalID',
        :'inProgressRequesterID',
        null,
        'stripe'
    )->>'outcome',
    'offer-created',
    'Should accept ticket requests while the event remains in progress'
);

select results_eq(
    format(
        $$
            select
                ao.expires_at > current_timestamp,
                ao.expires_at <= e.ends_at,
                ao.status,
                eir.status
            from admission_offer ao
            join event e using (event_id)
            join event_invitation_request eir
                on eir.event_id = ao.event_id
                and eir.user_id = ao.user_id
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
        $$,
        :'eventInProgressApprovalID',
        :'inProgressRequesterID'
    ),
    $$ values (true, true, 'pending'::text, 'accepted'::text) $$,
    'Should bound the in-progress offer by event end'
);

-- Should reissue a reviewed ticket request after its previous offer is canceled.
select lives_ok(
    format(
        $$
        select cancel_event_admission_offer(
            %L::uuid,
            %L::uuid,
            (
                select admission_offer_id
                from admission_offer
                where event_id = %L::uuid
                and user_id = %L::uuid
                and status = 'pending'
            )
        )
        $$,
        :'actorID',
        :'groupID',
        :'eventPublicTicketApprovalID',
        :'requester4ID'
    ),
    'Should cancel the active approval offer before reissue'
);

select is(
    (
        select jsonb_build_object(
            'outcome', v_result->>'outcome',
            'promoted_user_ids', v_result->'promoted_user_ids'
        )
        from (
            select accept_event_invitation_request(
                :'actorID',
                :'groupID',
                :'eventPublicTicketApprovalID',
                :'requester4ID',
                null,
                'stripe'
            ) as v_result
        ) accept_result
    ),
    '{"outcome":"offer-created","promoted_user_ids":[]}'::jsonb,
    'Should reissue an offer for an accepted ticket request'
);

select is(
    (
        select jsonb_build_object(
            'active_count', count(*) filter (
                where status in ('checkout_pending', 'pending')
            ),
            'offer_count', count(*)
        )
        from admission_offer
        where event_id = :'eventPublicTicketApprovalID'::uuid
        and source = 'approval'
        and user_id = :'requester4ID'::uuid
    ),
    '{"active_count":1,"offer_count":2}'::jsonb,
    'Should retain offer history with one active reissued offer'
);

select is(
    (
        select count(*)::int
        from audit_log
        where action = 'event_admission_offer_reissued'
        and event_id = :'eventPublicTicketApprovalID'::uuid
        and resource_id = :'requester4ID'::uuid
    ),
    1,
    'Should audit the approval offer reissue'
);

-- Should require an organizer-selected invitation-only tier for generic requests
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L)',
        :'actorID',
        :'groupID',
        :'eventPrivateTicketApprovalID',
        :'requester3ID',
        :'privateTicketTypeID',
        'stripe'
    ),
    'Should assign an invitation-only tier to a generic request'
);

-- Should create the assigned private-tier offer
select is(
    (
        select jsonb_build_array(ao.source, ao.status, ao.event_ticket_type_id)
        from admission_offer ao
        where ao.event_id = :'eventPrivateTicketApprovalID'::uuid
        and ao.user_id = :'requester3ID'::uuid
    ),
    format('["approval","pending","%s"]', :'privateTicketTypeID')::jsonb,
    'Should create the assigned private-tier approval offer'
);

-- Should enqueue approval notifications transactionally
select is(
    (
        select count(*)::int
        from notification
        where kind = 'event-ticket-request-approved'
        and user_id in (:'requester3ID'::uuid, :'requester4ID'::uuid)
    ),
    3,
    'Should enqueue one notification for each initial or reissued approval offer'
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
                    where ao.event_id = :'eventPrivateTicketApprovalID'::uuid
                    and ao.user_id = :'requester3ID'::uuid
                    and ao.status = 'pending'
                )
            ),
            'event_id', :'eventPrivateTicketApprovalID',
            'event_ticket_type_id', :'privateTicketTypeID',
            'theme', jsonb_build_object('primary_color', '#2563eb'),
            'ticket_title', 'Private admission',
            'timezone', 'UTC',
            'user_id', :'requester3ID'
        )
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-ticket-request-approved'
        and n.user_id = :'requester3ID'
    ),
    'Should enqueue complete approved ticket request context'
);

-- Should preserve queue priority when accepting a public-tier request
select is(
    accept_event_invitation_request(
        :'actorID',
        :'groupID',
        :'eventQueuePriorityID',
        :'queuePriorityRequesterID',
        null,
        'stripe'
    ),
    '{"conflict":"queue-has-priority","promoted_user_ids":[]}'::jsonb,
    'Should preserve queue priority when accepting a public-tier request'
);

-- Should promote the queue head without reviewing the competing request
select is(
    (
        select jsonb_build_object(
            'approval_offer_count', (
                select count(*)
                from admission_offer ao
                where ao.event_id = :'eventQueuePriorityID'::uuid
                and ao.user_id = :'queuePriorityRequesterID'::uuid
            ),
            'request_status', (
                select eir.status
                from event_invitation_request eir
                where eir.event_id = :'eventQueuePriorityID'::uuid
                and eir.user_id = :'queuePriorityRequesterID'::uuid
            ),
            'waitlist_offer_status', (
                select ao.status
                from admission_offer ao
                where ao.event_id = :'eventQueuePriorityID'::uuid
                and ao.source = 'waitlist'
                and ao.user_id = :'queuePriorityWaitlistUserID'::uuid
            ),
            'waitlist_row_count', (
                select count(*)
                from event_waitlist ew
                where ew.event_id = :'eventQueuePriorityID'::uuid
                and ew.user_id = :'queuePriorityWaitlistUserID'::uuid
            )
        )
    ),
    '{"approval_offer_count":0,"request_status":"pending","waitlist_offer_status":"pending","waitlist_row_count":0}'::jsonb,
    'Should promote the queue head without reviewing the competing request'
);

-- Should report a sold-out conflict without reviewing the request
select is(
    accept_event_invitation_request(
        :'actorID',
        :'groupID',
        :'eventTicketSoldOutID',
        :'soldOutRequesterID',
        null,
        'stripe'
    ),
    '{"conflict":"ticket-type-sold-out","promoted_user_ids":[]}'::jsonb,
    'Should report a sold-out conflict without reviewing the request'
);

-- Should retain sold-out enrollment state after the conflict
select is(
    (
        select jsonb_build_object(
            'approval_offer_count', (
                select count(*)
                from admission_offer ao
                where ao.event_id = :'eventTicketSoldOutID'::uuid
                and ao.user_id = :'soldOutRequesterID'::uuid
            ),
            'occupant_offer_status', (
                select ao.status
                from admission_offer ao
                where ao.event_id = :'eventTicketSoldOutID'::uuid
                and ao.user_id = :'soldOutOccupantID'::uuid
            ),
            'request_status', (
                select eir.status
                from event_invitation_request eir
                where eir.event_id = :'eventTicketSoldOutID'::uuid
                and eir.user_id = :'soldOutRequesterID'::uuid
            )
        )
    ),
    '{"approval_offer_count":0,"occupant_offer_status":"pending","request_status":"pending"}'::jsonb,
    'Should retain sold-out enrollment state after the conflict'
);

-- Should reactivate canceled attendance when accepting a new request
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventAttendanceCanceledID', :'requester7ID'
    ),
    'Should reactivate canceled attendance when accepting a new request'
);

-- Should clear canceled attendance metadata after reactivation
select results_eq(
    format($$
        select
            attendance_canceled_at,
            attendance_canceled_by_user_id,
            status
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventAttendanceCanceledID', :'requester7ID'),
    $$ values (null::timestamptz, null::uuid, 'confirmed'::text) $$,
    'Should clear canceled attendance metadata after reactivation'
);

-- Should accept a pending invitation request
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requesterID'
    ),
    'Should accept a pending invitation request'
);

-- Should mark the request accepted
select results_eq(
    format(
        $$
            select status, reviewed_by is not null, reviewed_at is not null
            from event_invitation_request
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'requesterID'
    ),
    $$ values ('accepted'::text, true, true) $$,
    'Should mark the request accepted'
);

-- Should create a confirmed attendee row
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'requesterID'::uuid
        and manually_invited = false
    ),
    'Should create a confirmed attendee row that is not manually invited'
);

-- Should accept after reconciling expired RSVP reservations
select is(
    accept_event_invitation_request(
        :'actorID',
        :'groupID',
        :'eventExpiredReservationID',
        :'expiredReservationRequesterID'
    ),
    format(
        '{"outcome":"attendee","promoted_user_ids":["%s"],"user_id":"%s"}',
        :'expiredReservationWaitlistUserID',
        :'expiredReservationRequesterID'
    )::jsonb,
    'Should accept after reconciling expired RSVP reservations'
);

select is(
    (
        select jsonb_build_object(
            'offer_statuses', (
                select jsonb_agg(ao.status order by ao.admission_offer_id)
                from admission_offer ao
                where ao.admission_offer_id in (
                    :'expiredReservationOfferOneID'::uuid,
                    :'expiredReservationOfferTwoID'::uuid
                )
            ),
            'promoted_status', (
                select ea.status
                from event_attendee ea
                where ea.event_id = :'eventExpiredReservationID'::uuid
                and ea.user_id = :'expiredReservationWaitlistUserID'::uuid
            ),
            'request_status', (
                select eir.status
                from event_invitation_request eir
                where eir.event_id = :'eventExpiredReservationID'::uuid
                and eir.user_id = :'expiredReservationRequesterID'::uuid
            )
        )
    ),
    '{"offer_statuses":["expired","expired"],"promoted_status":"confirmed","request_status":"accepted"}'::jsonb,
    'Should persist expired RSVP reservation reconciliation before accepting'
);

-- Should reuse a canceled manual invitation row without marking it manually invited
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requester2ID'
    ),
    'Should accept a request with a canceled manual invitation row'
);

select results_eq(
    format(
        $$
            select status, manually_invited
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'requester2ID'
    ),
    $$ values ('confirmed'::text, false) $$,
    'Should keep reused canceled invitation request attendees not manually invited'
);

-- Should confirm an existing pending manual invitation row
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventPendingInvitationID', :'requester3ID'
    ),
    'Should accept a request with a pending manual invitation row'
);

select results_eq(
    format(
        $$
            select status, manually_invited
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventPendingInvitationID',
        :'requester3ID'
    ),
    $$ values ('confirmed'::text, true) $$,
    'Should keep reused pending invitation request attendees manually invited'
);

-- Should track the acceptance in the audit log
select results_eq(
    format(
        $$
        select
            action,
            actor_user_id,
            community_id,
            details,
            event_id,
            group_id,
            resource_id,
            resource_type
        from audit_log
        where action = 'event_invitation_request_accepted'
        and resource_id = %L::uuid
        $$,
        :'requesterID'
    ),
    format(
        $$
        values (
            'event_invitation_request_accepted',
            %L::uuid,
            %L::uuid,
            '{"event_id": "%s", "user_id": "%s"}'::jsonb,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user'
        )
        $$,
        :'actorID', :'communityID', :'eventID', :'requesterID', :'eventID', :'groupID', :'requesterID'
    ),
    'Should track the acceptance in the audit log'
);

-- Should reject accepting when event capacity is full
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventFullID', :'requesterID'
    ),
    'event has reached capacity',
    'Should reject accepting when event capacity is full'
);

-- Should reject accepting when event is unpublished
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventUnpublishedID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event is unpublished'
);

-- Should reject accepting when event belongs to an inactive group
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'inactiveGroupID', :'eventInactiveGroupID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event belongs to an inactive group'
);

-- Should reject accepting when event approval is disabled
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventApprovalDisabledID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event approval is disabled'
);

-- Should reject accepting when event is past
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventPastID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event is past'
);

-- Should accept attendee requests after registration closes while the event remains active
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventRegistrationOpenUntilStartID', :'requester6ID'
    ),
    'Should accept attendee requests after registration closes while the event remains active'
);

-- Should reject accepting an already reviewed request
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requesterID'
    ),
    'pending invitation request not found',
    'Should reject accepting an already reviewed request'
);

-- Should reject accepting when the requester is already attending
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventAttendeeConflictID', :'requester4ID'
    ),
    'user is already attending this event',
    'Should reject accepting when the requester is already attending'
);

-- Should reject accepting when the requester rejected an organizer invitation
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventAttendeeConflictID', :'requester5ID'
    ),
    'user rejected an invitation for this event',
    'Should reject accepting when the requester rejected an organizer invitation'
);

-- Should keep conflicting requests pending and attendee rows unchanged
select is(
    (
        select jsonb_build_object(
            'attendee_statuses', (
                select jsonb_agg(status order by user_id)
                from event_attendee
                where event_id = :'eventAttendeeConflictID'::uuid
            ),
            'request_statuses', (
                select jsonb_agg(status order by user_id)
                from event_invitation_request
                where event_id = :'eventAttendeeConflictID'::uuid
            )
        )
    ),
    '{"attendee_statuses": ["confirmed", "invitation-rejected"], "request_statuses": ["pending", "pending"]}'::jsonb,
    'Should keep conflicting requests pending and attendee rows unchanged'
);

-- Should accept invitation requests that include registration answers
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventQuestionsApprovalID', :'questionsAcceptedRequestUserID'
    ),
    'Should accept invitation requests that include registration answers'
);

-- Should copy request answers to the attendee row
select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventQuestionsApprovalID'::uuid
        and user_id = :'questionsAcceptedRequestUserID'::uuid
    ),
    format(
        '{"answers": [{"question_id": "%s", "value": "Accepted request answer"}]}',
        :'registrationQuestionID'
    )::jsonb,
    'Should copy request answers to the attendee row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
