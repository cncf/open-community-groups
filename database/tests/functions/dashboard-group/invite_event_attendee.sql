-- Tests creating organizer event invitations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(59);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a130000-0000-0000-0000-000000000001'
\set canceledAttendeeUserID '3a130000-0000-0000-0000-000000000019'
\set capacityEventID '3a130000-0000-0000-0000-000000000021'
\set capacityInviteUserID '3a130000-0000-0000-0000-000000000022'
\set capacityPriceWindowID '3a130000-0000-0000-0000-00000000008b'
\set capacityQueueUserID '3a130000-0000-0000-0000-000000000023'
\set capacityTicketTypeID '3a130000-0000-0000-0000-00000000008c'
\set communityID '3a130000-0000-0000-0000-000000000003'
\set confirmedAttendeeUserID '3a130000-0000-0000-0000-000000000004'
\set eventCategoryID '3a130000-0000-0000-0000-000000000005'
\set eventID '3a130000-0000-0000-0000-000000000006'
\set eventQuestionsID '3a130000-0000-0000-0000-000000000007'
\set eventQuestionsPriceWindowID '3a130000-0000-0000-0000-00000000008d'
\set eventQuestionsTicketTypeID '3a130000-0000-0000-0000-00000000008e'
\set expiredReservationEventID '3a130000-0000-0000-0000-00000000003f'
\set expiredReservationInviteUserID '3a130000-0000-0000-0000-000000000040'
\set expiredReservationOfferID '3a130000-0000-0000-0000-000000000041'
\set expiredReservationOfferUserID '3a130000-0000-0000-0000-000000000042'
\set expiredReservationPriceWindowID '3a130000-0000-0000-0000-00000000008f'
\set expiredReservationPromotedUserID '3a130000-0000-0000-0000-000000000043'
\set expiredReservationTicketTypeID '3a130000-0000-0000-0000-000000000090'
\set expiredWaitlistOfferID '3a130000-0000-0000-0000-00000000007b'
\set expiredWaitlistOfferUserID '3a130000-0000-0000-0000-00000000007a'
\set groupCategoryID '3a130000-0000-0000-0000-000000000008'
\set groupID '3a130000-0000-0000-0000-000000000009'
\set inProgressEventID '3a130000-0000-0000-0000-000000000025'
\set inProgressInviteUserID '3a130000-0000-0000-0000-000000000026'
\set inProgressPriceWindowID '3a130000-0000-0000-0000-000000000027'
\set inProgressTicketTypeID '3a130000-0000-0000-0000-000000000028'
\set invalidTicketUserID '3a130000-0000-0000-0000-000000000029'
\set lapsedCheckoutEventID '3a130000-0000-0000-0000-00000000007c'
\set lapsedCheckoutPriceWindowID '3a130000-0000-0000-0000-00000000007d'
\set lapsedCheckoutTicketTypeID '3a130000-0000-0000-0000-00000000007e'
\set lapsedCheckoutUserID '3a130000-0000-0000-0000-00000000007f'
\set lapsedOfferEventID '3a130000-0000-0000-0000-000000000080'
\set lapsedOfferID '3a130000-0000-0000-0000-000000000081'
\set lapsedOfferPriceWindowID '3a130000-0000-0000-0000-000000000082'
\set lapsedOfferTicketTypeID '3a130000-0000-0000-0000-000000000083'
\set lapsedOfferUserID '3a130000-0000-0000-0000-000000000084'
\set lapsedPurchaseID '3a130000-0000-0000-0000-000000000085'
\set paidContextGroupID '3a130000-0000-0000-0000-00000000004a'
\set paidEventID '3a130000-0000-0000-0000-00000000002a'
\set paidInviteUserID '3a130000-0000-0000-0000-00000000002b'
\set paidPriceWindowID '3a130000-0000-0000-0000-00000000002c'
\set paidReadyEventID '3a130000-0000-0000-0000-00000000004e'
\set paidReadyInviteUserID '3a130000-0000-0000-0000-00000000004f'
\set paidReadyPriceWindowID '3a130000-0000-0000-0000-000000000050'
\set paidReadyTicketTypeID '3a130000-0000-0000-0000-000000000051'
\set paidTicketTypeID '3a130000-0000-0000-0000-00000000002d'
\set pendingRegistrationUserID '3a130000-0000-0000-0000-00000000008a'
\set privateSimpleEventID '3a130000-0000-0000-0000-000000000087'
\set privateSimpleInviteUserID '3a130000-0000-0000-0000-000000000046'
\set privateSimplePriceWindowID '3a130000-0000-0000-0000-000000000047'
\set privateSimplePublicPriceWindowID '3a130000-0000-0000-0000-000000000088'
\set privateSimplePublicTicketTypeID '3a130000-0000-0000-0000-000000000089'
\set privateSimpleTicketTypeID '3a130000-0000-0000-0000-000000000048'
\set questionsInvitedUserID '3a130000-0000-0000-0000-000000000010'
\set queueConflictEventID '3a130000-0000-0000-0000-00000000002e'
\set queueConflictInviteUserID '3a130000-0000-0000-0000-00000000002f'
\set queueConflictPriceWindowID '3a130000-0000-0000-0000-000000000030'
\set queueConflictTicketTypeID '3a130000-0000-0000-0000-000000000031'
\set queueConflictWaitlistUserID '3a130000-0000-0000-0000-000000000032'
\set queueOfferEventID '3a130000-0000-0000-0000-000000000033'
\set queueOfferPriceWindowID '3a130000-0000-0000-0000-000000000034'
\set queueOfferTicketTypeID '3a130000-0000-0000-0000-000000000035'
\set queueOfferUserID '3a130000-0000-0000-0000-000000000036'
\set registeredUserID '3a130000-0000-0000-0000-000000000011'
\set registrationQuestionID '3a130000-0000-0000-0000-000000000012'
\set rejectedUserID '3a130000-0000-0000-0000-000000000013'
\set simplePriceWindowID '3a130000-0000-0000-0000-000000000091'
\set simpleTicketTypeID '3a130000-0000-0000-0000-000000000092'
\set siteID '3a130000-0000-0000-0000-000000000024'
\set soldOutAttendeeUserID '3a130000-0000-0000-0000-000000000086'
\set soldOutInviteUserID '3a130000-0000-0000-0000-000000000037'
\set soldOutOccupantID '3a130000-0000-0000-0000-000000000038'
\set soldOutPriceWindowID '3a130000-0000-0000-0000-000000000039'
\set soldOutTicketedEventID '3a130000-0000-0000-0000-00000000003a'
\set soldOutTicketTypeID '3a130000-0000-0000-0000-00000000003b'
\set ticketedEventID '3a130000-0000-0000-0000-000000000014'
\set ticketPriceWindowID '3a130000-0000-0000-0000-000000000020'
\set ticketPriceWindowSecondaryID '3a130000-0000-0000-0000-000000000045'
\set ticketTypeID '3a130000-0000-0000-0000-000000000015'
\set ticketTypeSecondaryID '3a130000-0000-0000-0000-000000000044'
\set unavailableInviteUserID '3a130000-0000-0000-0000-00000000003c'
\set unavailablePriceWindowID '3a130000-0000-0000-0000-000000000093'
\set unavailableTicketEventID '3a130000-0000-0000-0000-00000000003d'
\set unavailableTicketTypeID '3a130000-0000-0000-0000-00000000003e'
\set unpublishedEventID '3a130000-0000-0000-0000-000000000016'
\set unpublishedPriceWindowID '3a130000-0000-0000-0000-000000000094'
\set unpublishedTicketTypeID '3a130000-0000-0000-0000-000000000095'
\set unverifiedUserID '3a130000-0000-0000-0000-000000000017'
\set waitlistedUserID '3a130000-0000-0000-0000-000000000018'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'capacityInviteUserID');
select fx_user(:'capacityQueueUserID');
select fx_user(:'invalidTicketUserID');
select fx_user(:'privateSimpleInviteUserID');
select fx_user(:'queueConflictInviteUserID');
select fx_user(:'queueConflictWaitlistUserID');
select fx_user(:'lapsedCheckoutUserID');
select fx_user(:'lapsedOfferUserID');
select fx_user(:'soldOutAttendeeUserID');
select fx_user(:'soldOutInviteUserID');
select fx_user(:'soldOutOccupantID');
select fx_user(:'unavailableInviteUserID');
select fx_user(:'questionsInvitedUserID');
select fx_user(:'paidReadyInviteUserID');
select fx_user(:'expiredReservationInviteUserID');
select fx_user(:'expiredReservationOfferUserID');
select fx_user(:'expiredReservationPromotedUserID');
select fx_user(:'canceledAttendeeUserID');
select fx_user(:'pendingRegistrationUserID');


-- Community
insert into site (description, site_id, theme, title)
values (
    'Event invitation site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Event Invitation Site'
);

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'General'));

-- Group owning events without payment readiness
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Test Group'));

-- Group with a valid payment recipient for paid invitations
select fx_group(:'paidContextGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{
        "provider": "stripe",
        "recipient_id": "acct_paid_invite",
        "seller_display_name": "Paid Invite Fiscal Sponsor"
    }'::jsonb));

-- Users
select fx_user(:'actorID', jsonb_build_object('username', 'actor-invite-event-attendee'));

select fx_user(:'confirmedAttendeeUserID', jsonb_build_object('username', 'confirmed-invite-event-attendee'));
select fx_user(:'inProgressInviteUserID', jsonb_build_object('username', 'in-progress-invite-event-attendee'));

select fx_user(:'paidInviteUserID', jsonb_build_object('name', 'Paid Invite'));

select fx_user(:'queueOfferUserID', jsonb_build_object('username', 'queue-offer'));
select fx_user(:'registeredUserID', jsonb_build_object(
    'email', 'registered-invite-event-attendee@example.com',
    'username', 'registered'
));
select fx_user(:'rejectedUserID', jsonb_build_object('username', 'rejected'));

select fx_user(:'unverifiedUserID', jsonb_build_object(
    'email', 'unverified-invite-event-attendee@example.com',
    'email_verified', false,
    'username', 'unverified-invite-event-attendee'
));
select fx_user(:'waitlistedUserID', jsonb_build_object('username', 'waitlisted'));
select fx_user(:'expiredWaitlistOfferUserID', jsonb_build_object('username', 'expired-waitlist-offer'));

-- Events
select fx_event(:'capacityEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'ticketedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Ticketed Event',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'paidEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'queueConflictEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));
select fx_event(:'queueOfferEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));
select fx_event(:'soldOutTicketedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'unavailableTicketEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '1 day'
));

-- Paid event with a complete venue for successful paid invitation snapshots
select fx_event(:'paidReadyEventID', :'paidContextGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_zip_code', '97201'
));

-- RSVP event whose expired reservation is reconciled before organizer invite allocation
select fx_event(:'expiredReservationEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));

-- Event whose lapsed waitlist offer is expired by reconciliation before the invite
select fx_event(:'lapsedOfferEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));

-- Event whose lapsed checkout registration is released by reconciliation before the invite
select fx_event(:'lapsedCheckoutEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Simple RSVP event that also offers a private invitation-only tier
select fx_event(:'privateSimpleEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- In-progress ticketed event that remains open for organizer invitations
select fx_event(:'inProgressEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 hours',
    'published', true,
    'starts_at', current_timestamp - interval '1 hour'
));

-- Event with registration questions before confirmation
select fx_event(:'eventQuestionsID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'registration_ends_at', current_timestamp - interval '1 hour',
    'registration_questions', format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'registrationQuestionID'
    )::jsonb,
    'starts_at', current_timestamp + interval '1 day'
));

-- Ticket types
select fx_event_ticket_type(:'inProgressTicketTypeID', :'inProgressEventID', jsonb_build_object('seats_total', 100));
select fx_event_ticket_type(:'lapsedCheckoutTicketTypeID', :'lapsedCheckoutEventID', jsonb_build_object('seats_total', 5));
select fx_event_ticket_type(:'lapsedOfferTicketTypeID', :'lapsedOfferEventID', jsonb_build_object('seats_total', 5));
select fx_event_ticket_type(:'paidTicketTypeID', :'paidEventID', jsonb_build_object('seats_total', 100));
select fx_event_ticket_type(:'queueConflictTicketTypeID', :'queueConflictEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'queueOfferTicketTypeID', :'queueOfferEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'soldOutTicketTypeID', :'soldOutTicketedEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'ticketTypeID', :'ticketedEventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General'
));
select fx_event_ticket_type(:'ticketTypeSecondaryID', :'ticketedEventID', jsonb_build_object(
    'order', 2,
    'seats_total', 25
));

-- Paid ticket tier used by the successful paid snapshot scenario
select fx_event_ticket_type(:'paidReadyTicketTypeID', :'paidReadyEventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'Paid ready admission'
));

-- Free public tier that keeps the private-tier event a simple RSVP
select fx_event_ticket_type(:'privateSimplePublicTicketTypeID', :'privateSimpleEventID', jsonb_build_object('seats_total', 10));

-- Private invitation-only tier on the simple RSVP event
select fx_event_ticket_type(:'privateSimpleTicketTypeID', :'privateSimpleEventID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 2,
    'seats_total', 10,
    'title', 'Private admission'
));

-- Inactive ticket type used to reject unavailable ticketed invitations
select fx_event_ticket_type(:'unavailableTicketTypeID', :'unavailableTicketEventID', jsonb_build_object(
    'active', false,
    'seats_total', 100
));

select fx_event_ticket_price_window(:'inProgressPriceWindowID', :'inProgressTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'lapsedCheckoutPriceWindowID', :'lapsedCheckoutTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'lapsedOfferPriceWindowID', :'lapsedOfferTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'paidPriceWindowID', :'paidTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'queueConflictPriceWindowID', :'queueConflictTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'queueOfferPriceWindowID', :'queueOfferTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'soldOutPriceWindowID', :'soldOutTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'ticketPriceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'ticketPriceWindowSecondaryID', :'ticketTypeSecondaryID', jsonb_build_object('amount_minor', 0));

-- Positive ticket price used by the successful paid snapshot scenario
select fx_event_ticket_price_window(:'paidReadyPriceWindowID', :'paidReadyTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Current free prices for the private-tier event's public and private tiers
select fx_event_ticket_price_window(:'privateSimplePublicPriceWindowID', :'privateSimplePublicTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'privateSimplePriceWindowID', :'privateSimpleTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Single-seat RSVP tiers for the capacity and expired-reservation events
select fx_event_ticket_type(:'capacityTicketTypeID', :'capacityEventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'expiredReservationTicketTypeID', :'expiredReservationEventID', jsonb_build_object('seats_total', 1));

-- Ten-seat RSVP tiers, leaving a free seat for each invitation scenario
select fx_event_ticket_type(:'eventQuestionsTicketTypeID', :'eventQuestionsID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'simpleTicketTypeID', :'eventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'unpublishedTicketTypeID', :'unpublishedEventID', jsonb_build_object('seats_total', 10));

-- Current free prices for the RSVP tiers
select fx_event_ticket_price_window(:'capacityPriceWindowID', :'capacityTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventQuestionsPriceWindowID', :'eventQuestionsTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'expiredReservationPriceWindowID', :'expiredReservationTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'simplePriceWindowID', :'simpleTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'unpublishedPriceWindowID', :'unpublishedTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current price on the inactive tier, so only its inactive state rejects the invitation
select fx_event_ticket_price_window(:'unavailablePriceWindowID', :'unavailableTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Existing attendees and invitation decisions
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'confirmedAttendeeUserID', 'confirmed'),
    (:'eventID', :'rejectedUserID', 'invitation-rejected');

-- Registration still waiting for answers, without a checkout hold to release
insert into event_attendee (event_id, manually_invited, status, user_id)
values (:'eventQuestionsID', false, 'registration-questions-pending', :'pendingRegistrationUserID');

-- Confirmed attendee on the sold-out tier; the occupant's pending offer already fills its single seat
insert into event_attendee (event_id, user_id, status)
values (:'soldOutTicketedEventID', :'soldOutAttendeeUserID', 'confirmed');

-- Checkout registration still waiting for answers after its purchase hold lapsed
insert into event_attendee (event_id, manually_invited, status, user_id)
values (:'lapsedCheckoutEventID', false, 'registration-questions-pending', :'lapsedCheckoutUserID');

-- Lapsed checkout hold expired by reconciliation before the invite
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
) values (
    0,
    'USD',
    :'lapsedCheckoutEventID',
    :'lapsedPurchaseID',
    :'lapsedCheckoutTicketTypeID',
    current_timestamp - interval '1 hour',
    'pending',
    'Lapsed checkout admission',
    :'lapsedCheckoutUserID'
);

-- Canceled attendee row reused by a new organizer invitation
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    registration_answers,
    status,
    user_id
) values (
    current_timestamp,
    :'actorID',
    :'eventID',
    '{"answers": [{"value": "Stale"}]}'::jsonb,
    'attendance-canceled',
    :'canceledAttendeeUserID'
);

-- Existing waitlist entries
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values
    (
        :'capacityEventID',
        :'capacityTicketTypeID',
        :'capacityQueueUserID'
    ),
    (
        :'eventID',
        :'simpleTicketTypeID',
        :'waitlistedUserID'
    );

-- Expired RSVP organizer offer swept before the invitation capacity check
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'expiredReservationOfferID',
    current_timestamp - interval '2 hours',
    :'expiredReservationEventID',
    :'expiredReservationTicketTypeID',
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'pending',
    :'expiredReservationOfferUserID'
);

-- RSVP waitlist user promoted when the expired reservation is swept
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'expiredReservationEventID',
    :'expiredReservationTicketTypeID',
    :'expiredReservationPromotedUserID'
);

-- Ticketed waitlist target promoted into a queue offer during organizer invite
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'queueOfferEventID',
    :'queueOfferTicketTypeID',
    :'queueOfferUserID'
);

-- Ticketed waitlist head that receives priority over a new organizer invite
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'queueConflictEventID',
    :'queueConflictTicketTypeID',
    :'queueConflictWaitlistUserID'
);

-- Expired waitlist promotion that organizers can reissue from the waitlist page
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'expiredWaitlistOfferID',
    current_timestamp - interval '2 days',
    :'eventID',
    :'simpleTicketTypeID',
    current_timestamp - interval '1 day',
    'waitlist',
    'expired',
    :'expiredWaitlistOfferUserID'
);

-- Lapsed waitlist offer still pending until reconciliation expires it
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'lapsedOfferID',
    current_timestamp - interval '2 days',
    :'lapsedOfferEventID',
    :'lapsedOfferTicketTypeID',
    current_timestamp - interval '1 hour',
    'waitlist',
    'pending',
    :'lapsedOfferUserID'
);

-- Active ticket offer occupying the sold-out ticketed tier
insert into admission_offer (
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'soldOutTicketedEventID',
    :'soldOutTicketTypeID',
    current_timestamp + interval '12 hours',
    'organizer_invitation',
    'pending',
    :'soldOutOccupantID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject invitations with both user_id and email
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, 'registered-invite-event-attendee@example.com') $$,
        :'actorID', :'groupID', :'eventID', :'registeredUserID'
    ),
    'OCG01',
    'provide exactly one invite target',
    'Should reject invitations with both user_id and email'
);

-- Should invite a registered user
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'eventID',
        :'registeredUserID',
        null
    )->>'user_id',
    :'registeredUserID',
    'Should auto-select the sole tier and return the registered invitee id'
);

select results_eq(
    format(
        $$
        select source, status
        from admission_offer
        where event_id = %L::uuid
        and user_id = %L::uuid
        $$,
        :'eventID', :'registeredUserID'
    ),
    $$ values ('organizer_invitation'::text, 'pending'::text) $$,
    'Should create a pending organizer invitation offer for a registered user'
);

-- Should create the expected audit row for a registered user invitation
select results_eq(
    format(
        $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            details - 'admission_offer_id',
            event_id,
            group_id,
            resource_id,
            resource_type
        from audit_log
        where action = 'event_attendee_invitation_sent'
        and resource_id = %L::uuid
        $$,
        :'registeredUserID'
    ),
    format(
        $$
        values (
            'event_attendee_invitation_sent',
            %L::uuid,
            'actor-invite-event-attendee',
            %L::uuid,
            '{
                "event_id": "%s",
                "event_ticket_type_id": "%s",
                "registration_questions_required": false,
                "user_id": "%s"
            }'::jsonb,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user'
        )
        $$,
        :'actorID',
        :'communityID',
        :'eventID',
        :'simpleTicketTypeID',
        :'registeredUserID',
        :'eventID',
        :'groupID',
        :'registeredUserID'
    ),
    'Should create the expected audit row for a registered user invitation'
);

-- Should create a private-tier offer on a simple RSVP event
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'privateSimpleEventID',
        :'privateSimpleInviteUserID',
        null,
        :'privateSimpleTicketTypeID'
    )->>'outcome',
    'offer-created',
    'Should create a private-tier offer on a simple RSVP event'
);

-- Should use ticket wording for a private-tier invitation on a simple RSVP event
select is(
    (
        select (ntd.data->>'is_simple_rsvp')::boolean
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-admission-offer-created'
        and n.user_id = :'privateSimpleInviteUserID'::uuid
    ),
    false,
    'Should use ticket wording for a private-tier invitation on a simple RSVP event'
);

-- Should reject re-inviting users with a pending invitation
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'eventID', :'registeredUserID', :'simpleTicketTypeID'
    ),
    'OCG01',
    'user already has a pending event invitation',
    'Should reject re-inviting users with a pending invitation'
);

-- Should reject re-inviting confirmed attendees
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'eventID', :'confirmedAttendeeUserID', :'simpleTicketTypeID'
    ),
    'OCG01',
    'user is already attending this event',
    'Should reject re-inviting confirmed attendees'
);

-- Should reject inviting users who still owe registration answers
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'eventQuestionsID', :'pendingRegistrationUserID', :'eventQuestionsTicketTypeID'
    ),
    'OCG01',
    'user already has a pending event registration',
    'Should reject inviting users who still owe registration answers'
);

-- Should reject inviting unverified registered users by id
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'eventID', :'unverifiedUserID', :'simpleTicketTypeID'
    ),
    'OCG01',
    'registered user not found',
    'Should reject inviting unverified registered users by id'
);

-- Should preserve queue priority before allocating organizer invitations
select is(
    (
        select status
        from admission_offer
        where event_id = :'eventID'::uuid
        and user_id = :'waitlistedUserID'::uuid
    ),
    'pending',
    'Should promote the existing waitlist before creating a new invitation'
);

select is(
    (
        select count(*)
        from event_waitlist
        where event_id = :'eventID'::uuid
        and user_id = :'waitlistedUserID'::uuid
    ),
    0::bigint,
    'Should remove the promoted user from the waitlist'
);

-- Should reject inviting a user with an active waitlist offer
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'eventID', :'waitlistedUserID', :'simpleTicketTypeID'
    ),
    'OCG01',
    'user already has a pending event invitation',
    'Should reject inviting a user with an active waitlist offer'
);

-- Should invite a user whose waitlist offer expired
select is(
    invite_event_attendee(
        :'actorID', :'groupID', :'eventID', :'expiredWaitlistOfferUserID', null, :'simpleTicketTypeID'
    ) ->> 'outcome',
    'offer-created',
    'Should create a new organizer offer for a user whose waitlist offer expired'
);

select results_eq(
    format(
        $$
        select source, status
        from admission_offer
        where event_id = %L::uuid
        and user_id = %L::uuid
        order by created_at
        $$,
        :'eventID', :'expiredWaitlistOfferUserID'
    ),
    $$
        values
            ('waitlist', 'expired'),
            ('organizer_invitation', 'pending')
    $$,
    'Should keep the expired waitlist offer next to the new organizer offer'
);

-- Should pre-register an email invitee and keep them out of normal registration state
select ok(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'eventID',
        null,
        'new-invite-event-attendee@example.com',
        :'simpleTicketTypeID'
    ) is not null,
    'Should invite by email'
);

select is(
    (
        select registration_status
        from "user"
        where email = 'new-invite-event-attendee@example.com'
    ),
    'pre-registered',
    'Should create a pre-registered user for an email invite'
);

select results_eq(
    format(
        $$
        select
            ao.source,
            ao.status,
            u.email,
            u.registration_status
        from admission_offer ao
        join "user" u using (user_id)
        where ao.event_id = %L::uuid
        and u.email = 'new-invite-event-attendee@example.com'
        $$,
        :'eventID'
    ),
    $$
        values (
            'organizer_invitation',
            'pending',
            'new-invite-event-attendee@example.com',
            'pre-registered'
        )
    $$,
    'Should create a pending offer for an email invite'
);

-- Should reject email invites for registered users with unverified email
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, null, 'unverified-invite-event-attendee@example.com', %L) $$,
        :'actorID', :'groupID', :'eventID', :'simpleTicketTypeID'
    ),
    'OCG01',
    'registered user email is not verified',
    'Should reject email invites for registered users with unverified email'
);

-- Should allow canceling and re-inviting pending offers
select lives_ok(
    format(
        $$ select cancel_event_admission_offer(%L, %L, %L) $$,
        :'actorID',
        :'groupID',
        (
            select admission_offer_id
            from admission_offer
            where event_id = :'eventID'::uuid
            and user_id = :'registeredUserID'::uuid
            and status = 'pending'
        )
    ),
    'Should cancel a pending invitation offer'
);

select lives_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'eventID', :'registeredUserID', :'simpleTicketTypeID'
    ),
    'Should allow re-inviting after cancellation'
);

-- Should reuse a canceled attendance row when inviting the attendee again
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'eventID',
        :'canceledAttendeeUserID',
        null,
        :'simpleTicketTypeID'
    )->>'user_id',
    :'canceledAttendeeUserID',
    'Should allow inviting a canceled attendee again'
);

select results_eq(
    format(
        $$
        select
            ea.status,
            ao.source,
            ao.status
        from event_attendee ea
        join admission_offer ao using (event_id, user_id)
        where ea.event_id = %L::uuid
        and ea.user_id = %L::uuid
        $$,
        :'eventID', :'canceledAttendeeUserID'
    ),
    $$ values (
        'attendance-canceled'::text,
        'organizer_invitation'::text,
        'pending'::text
    ) $$,
    'Should retain canceled attendance history while creating the invitation offer'
);

-- Should allow organizers to re-invite users that declined an earlier invitation
select lives_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'eventID', :'rejectedUserID', :'simpleTicketTypeID'
    ),
    'Should allow re-inviting a user that rejected an earlier invitation'
);

-- Should require a selected tier when multiple active tiers are available
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null) $$,
        :'actorID', :'groupID', :'ticketedEventID', :'registeredUserID'
    ),
    'OCG01',
    'ticket type is required for event invitations',
    'Should require a selected tier for multi-tier event invitations'
);

-- Should reject unavailable ticket types for event invitations
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID',
        :'groupID',
        :'unavailableTicketEventID',
        :'unavailableInviteUserID',
        :'unavailableTicketTypeID'
    ),
    'OCG01',
    'ticket type is not available',
    'Should reject unavailable ticket types for event invitations'
);

-- Should reject ticket types selected for a different event
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID',
        :'groupID',
        :'eventID',
        :'invalidTicketUserID',
        :'ticketTypeID'
    ),
    'OCG01',
    'ticket type is not available',
    'Should reject ticket types selected for a different event'
);

-- Should reject paid ticket invitations when payment readiness fails
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L, %L) $$,
        :'actorID',
        :'groupID',
        :'paidEventID',
        :'paidInviteUserID',
        :'paidTicketTypeID',
        'stripe'
    ),
    'OCG01',
    'paid-capable events require a payment recipient',
    'Should reject paid ticket invitations when payment readiness fails'
);

-- Should return a queue offer when reconciliation promotes the invitee
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'queueOfferEventID',
        :'queueOfferUserID',
        null,
        :'queueOfferTicketTypeID'
    )->>'outcome',
    'queue-offer',
    'Should return a queue offer when reconciliation promotes the invitee'
);

select is(
    (
        select jsonb_build_object(
            'offer_source', ao.source,
            'offer_status', ao.status,
            'waitlist_count', (
                select count(*)::int
                from event_waitlist ew
                where ew.event_id = :'queueOfferEventID'::uuid
                and ew.user_id = :'queueOfferUserID'::uuid
            )
        )
        from admission_offer ao
        where ao.event_id = :'queueOfferEventID'::uuid
        and ao.user_id = :'queueOfferUserID'::uuid
    ),
    '{"offer_source":"waitlist","offer_status":"pending","waitlist_count":0}'::jsonb,
    'Should preserve the promoted queue offer without creating an organizer invitation'
);

-- Should report queue priority when reconciliation fills the ticket tier
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'queueConflictEventID',
        :'queueConflictInviteUserID',
        null,
        :'queueConflictTicketTypeID'
    ),
    '{"conflict":"queue-has-priority"}'::jsonb,
    'Should report queue priority when reconciliation fills the ticket tier'
);

select is(
    (
        select jsonb_build_object(
            'invite_offer_count', (
                select count(*)::int
                from admission_offer ao
                where ao.event_id = :'queueConflictEventID'::uuid
                and ao.user_id = :'queueConflictInviteUserID'::uuid
            ),
            'waitlist_offer_status', (
                select ao.status
                from admission_offer ao
                where ao.event_id = :'queueConflictEventID'::uuid
                and ao.user_id = :'queueConflictWaitlistUserID'::uuid
            )
        )
    ),
    '{"invite_offer_count":0,"waitlist_offer_status":"pending"}'::jsonb,
    'Should keep the promoted queue offer after a queue-priority conflict'
);

-- Should report sold-out ticket tiers without creating an offer
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'soldOutTicketedEventID',
        :'soldOutInviteUserID',
        null,
        :'soldOutTicketTypeID'
    ),
    '{"conflict":"ticket-type-sold-out"}'::jsonb,
    'Should report sold-out ticket tiers without creating an offer'
);

select is(
    (
        select count(*)::int
        from admission_offer
        where event_id = :'soldOutTicketedEventID'::uuid
        and user_id = :'soldOutInviteUserID'::uuid
    ),
    0,
    'Should not create an offer for a sold-out ticket tier'
);

-- Should reject re-inviting a pending invitee before reporting a full tier
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'soldOutTicketedEventID', :'soldOutOccupantID', :'soldOutTicketTypeID'
    ),
    'OCG01',
    'user already has a pending event invitation',
    'Should reject re-inviting a pending invitee before reporting a full tier'
);

-- Should reject re-inviting a confirmed attendee before reporting a full tier
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'soldOutTicketedEventID', :'soldOutAttendeeUserID', :'soldOutTicketTypeID'
    ),
    'OCG01',
    'user is already attending this event',
    'Should reject re-inviting a confirmed attendee before reporting a full tier'
);

-- Should invite a user whose lapsed offer is expired by reconciliation
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'lapsedOfferEventID',
        :'lapsedOfferUserID',
        null,
        :'lapsedOfferTicketTypeID'
    )->>'outcome',
    'offer-created',
    'Should invite a user whose lapsed offer is expired by reconciliation'
);

select results_eq(
    format(
        $$
        select source, status
        from admission_offer
        where event_id = %L::uuid
        and user_id = %L::uuid
        order by created_at
        $$,
        :'lapsedOfferEventID', :'lapsedOfferUserID'
    ),
    $$
        values
            ('waitlist', 'expired'),
            ('organizer_invitation', 'pending')
    $$,
    'Should expire the lapsed waitlist offer before creating the organizer offer'
);

-- Should invite a user whose lapsed checkout registration is released by reconciliation
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'lapsedCheckoutEventID',
        :'lapsedCheckoutUserID',
        null,
        :'lapsedCheckoutTicketTypeID'
    )->>'outcome',
    'offer-created',
    'Should invite a user whose lapsed checkout registration is released by reconciliation'
);

select is(
    (
        select jsonb_build_object(
            'attendee_rows', (
                select count(*)::int
                from event_attendee ea
                where ea.event_id = :'lapsedCheckoutEventID'::uuid
                and ea.user_id = :'lapsedCheckoutUserID'::uuid
            ),
            'purchase_status', (
                select ep.status
                from event_purchase ep
                where ep.event_purchase_id = :'lapsedPurchaseID'::uuid
            )
        )
    ),
    '{"attendee_rows": 0, "purchase_status": "expired"}'::jsonb,
    'Should release the lapsed checkout registration before creating the organizer offer'
);

-- Should create in-progress event invitations with future offer expiry
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'inProgressEventID',
        :'inProgressInviteUserID',
        null,
        :'inProgressTicketTypeID'
    )->>'outcome',
    'offer-created',
    'Should create in-progress event invitations with future offer expiry'
);

-- Should keep in-progress invitation expiry within the remaining event window
select ok(
    (
        select ao.expires_at > current_timestamp
            and ao.expires_at <= e.ends_at
        from admission_offer ao
        join event e using (event_id)
        where ao.event_id = :'inProgressEventID'::uuid
        and ao.user_id = :'inProgressInviteUserID'::uuid
    ),
    'Should keep in-progress invitation expiry within the remaining event window'
);

-- Should create an organizer invitation
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'ticketedEventID',
        :'registeredUserID',
        null,
        :'ticketTypeID'
    )->>'user_id',
    :'registeredUserID',
    'Should create an organizer invitation'
);

-- Should reserve the organizer-selected ticket tier
select results_eq(
    format(
        $$
        select event_ticket_type_id, source, status
        from admission_offer
        where event_id = %L::uuid
        and user_id = %L::uuid
        $$,
        :'ticketedEventID', :'registeredUserID'
    ),
    format(
        $$ values (%L::uuid, 'organizer_invitation'::text, 'pending'::text) $$,
        :'ticketTypeID'
    ),
    'Should reserve the organizer-selected ticket tier'
);

-- Should persist a free issue-time price snapshot on the organizer invitation
select results_eq(
    format(
        $$
            select
                ao.amount_minor,
                ao.currency_code,
                ao.discount_amount_minor,
                ao.discount_code,
                ao.event_discount_code_id,
                ao.ticket_title
            from admission_offer ao
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
            and ao.status = 'pending'
        $$,
        :'ticketedEventID',
        :'registeredUserID'
    ),
    $$ values (
        0::bigint,
        null::text,
        0::bigint,
        null::text,
        null::uuid,
        'General'::text
    ) $$,
    'Should persist a free issue-time price snapshot on the organizer invitation'
);

-- Should create a paid organizer invitation
select is(
    invite_event_attendee(
        :'actorID',
        :'paidContextGroupID',
        :'paidReadyEventID',
        :'paidReadyInviteUserID',
        null,
        :'paidReadyTicketTypeID',
        'stripe'
    )->>'outcome',
    'offer-created',
    'Should create a paid organizer invitation'
);

-- Should persist a paid issue-time price snapshot on the organizer invitation
select results_eq(
    format(
        $$
            select
                ao.amount_minor,
                ao.currency_code,
                ao.discount_amount_minor,
                ao.discount_code,
                ao.event_discount_code_id,
                ao.ticket_title
            from admission_offer ao
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
            and ao.status = 'pending'
        $$,
        :'paidReadyEventID',
        :'paidReadyInviteUserID'
    ),
    $$ values (
        2500::bigint,
        'USD'::text,
        0::bigint,
        null::text,
        null::uuid,
        'Paid ready admission'::text
    ) $$,
    'Should persist a paid issue-time price snapshot on the organizer invitation'
);

-- Should enqueue complete organizer offer notification context
select is(
    (
        select ntd.data
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-admission-offer-created'
        and n.user_id = :'registeredUserID'
        and (ntd.data->>'event_id')::uuid = :'ticketedEventID'
    ),
    (
        select jsonb_build_object(
            'admission_offer_id', ao.admission_offer_id,
            'amount_minor', 0,
            'dashboard_url', format(
                '/dashboard/user?tab=invitations#event-offer-%s',
                ao.admission_offer_id
            ),
            'event_id', :'ticketedEventID',
            'event_name', 'Ticketed Event',
            'event_ticket_type_id', :'ticketTypeID',
            'expires_at', epoch_seconds(ao.expires_at),
            'group_name', 'Test Group',
            'is_simple_rsvp', false,
            'registration_questions_required', false,
            'theme', jsonb_build_object('primary_color', '#2563eb'),
            'ticket_title', 'General',
            'timezone', 'UTC',
            'user_id', :'registeredUserID'
        )
        from admission_offer ao
        where ao.event_id = :'ticketedEventID'
        and ao.user_id = :'registeredUserID'
        and ao.status = 'pending'
    ),
    'Should enqueue complete organizer offer notification context'
);

-- Should reject unpublished events
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'unpublishedEventID', :'registeredUserID', :'simpleTicketTypeID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject unpublished events'
);

-- Should create an offer when registration questions exist
select is(
    invite_event_attendee(
        :'actorID'::uuid,
        :'groupID'::uuid,
        :'eventQuestionsID'::uuid,
        :'questionsInvitedUserID'::uuid,
        null,
        :'eventQuestionsTicketTypeID'::uuid
    )->>'user_id',
    :'questionsInvitedUserID',
    'Should create an invitation offer when registration questions exist'
);

-- Should store a pending offer until registration questions are answered
select is(
    (
        select status
        from admission_offer
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsInvitedUserID'::uuid
    ),
    'pending',
    'Should store a pending organizer invitation offer'
);

select ok(
    (
        select expires_at > current_timestamp
        from admission_offer
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsInvitedUserID'::uuid
    ),
    'Should keep organizer invitations claimable after public registration closes'
);

-- Should preserve queue priority when expired reservations release capacity
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'expiredReservationEventID',
        :'expiredReservationInviteUserID',
        null,
        :'expiredReservationTicketTypeID'
    ),
    '{"conflict":"queue-has-priority"}'::jsonb,
    'Should preserve queue priority when expired reservations release capacity'
);

select is(
    (
        select jsonb_build_object(
            'offer_status', (
                select ao.status
                from admission_offer ao
                where ao.admission_offer_id = :'expiredReservationOfferID'::uuid
            ),
            'promoted_status', (
                select ao.status
                from admission_offer ao
                where ao.event_id = :'expiredReservationEventID'::uuid
                and ao.user_id = :'expiredReservationPromotedUserID'::uuid
            )
        )
    ),
    '{"offer_status":"expired","promoted_status":"pending"}'::jsonb,
    'Should persist the queue offer when expired reservations release capacity'
);

-- Should commit queue promotion before reporting an invitation conflict
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'capacityEventID',
        :'capacityInviteUserID',
        null,
        :'capacityTicketTypeID'
    ),
    '{"conflict":"queue-has-priority"}'::jsonb,
    'Should report that the existing queue consumed event capacity'
);

select is(
    (
        select status
        from admission_offer
        where event_id = :'capacityEventID'::uuid
        and user_id = :'capacityQueueUserID'::uuid
    ),
    'pending',
    'Should preserve the queue offer after the invitation conflict'
);

select is(
    (
        select count(*)::int
        from admission_offer
        where event_id = :'capacityEventID'::uuid
        and user_id = :'capacityInviteUserID'::uuid
    ),
    0,
    'Should not create an invitation after the queue consumes capacity'
);

select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'capacityEventID',
        null,
        'capacity-email@example.com',
        :'capacityTicketTypeID'
    ),
    '{"conflict":"ticket-type-sold-out"}'::jsonb,
    'Should report full capacity after the queue promotion'
);

select is(
    (
        select count(*)::int
        from "user"
        where email = 'capacity-email@example.com'
    ),
    0,
    'Should not pre-register an email target when no invitation is created'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
