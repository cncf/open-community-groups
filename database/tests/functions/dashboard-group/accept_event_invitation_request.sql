-- Tests accepting event invitation requests.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(68);

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
\set eventExternalReadyApprovalID '3a010000-0000-0000-0000-000000000070'
\set eventExternalUnreadyApprovalID '3a010000-0000-0000-0000-000000000071'
\set eventPaidNoRecipientApprovalID '3a010000-0000-0000-0000-000000000038'
\set eventPaidReadyApprovalID '3a010000-0000-0000-0000-000000000063'
\set externalReadyPriceWindowID '3a010000-0000-0000-0000-000000000072'
\set externalReadyRequesterID '3a010000-0000-0000-0000-000000000073'
\set externalReadyTicketTypeID '3a010000-0000-0000-0000-000000000074'
\set externalUnreadyPriceWindowID '3a010000-0000-0000-0000-000000000075'
\set externalUnreadyRequesterID '3a010000-0000-0000-0000-000000000076'
\set externalUnreadyTicketTypeID '3a010000-0000-0000-0000-000000000077'
\set groupExternalReadyID '3a010000-0000-0000-0000-000000000078'
\set groupExternalUnreadyID '3a010000-0000-0000-0000-000000000079'
\set eventPrivateTicketApprovalID '3a010000-0000-0000-0000-000000000027'
\set eventPublicTicketApprovalID '3a010000-0000-0000-0000-000000000028'
\set eventQuestionsApprovalID '3a010000-0000-0000-0000-000000000011'
\set eventQueuePriorityID '3a010000-0000-0000-0000-00000000002e'
\set eventRegistrationClosedApprovalID '3a010000-0000-0000-0000-000000000059'
\set eventRegistrationNotYetOpenID '3a010000-0000-0000-0000-00000000005a'
\set eventRegistrationOpenUntilStartID '3a010000-0000-0000-0000-000000000023'
\set eventReissueOfferBlockID '3a010000-0000-0000-0000-000000000039'
\set eventReissuePurchaseBlockID '3a010000-0000-0000-0000-00000000003a'
\set eventTicketSoldOutID '3a010000-0000-0000-0000-00000000002f'
\set eventUnpublishedID '3a010000-0000-0000-0000-000000000012'
\set eventUnavailableTicketApprovalID '3a010000-0000-0000-0000-00000000003b'
\set groupCategoryID '3a010000-0000-0000-0000-000000000013'
\set groupID '3a010000-0000-0000-0000-000000000014'
\set inactiveGroupID '3a010000-0000-0000-0000-000000000015'
\set closedAcceptRequesterID '3a010000-0000-0000-0000-00000000005b'
\set closedExpiredOfferID '3a010000-0000-0000-0000-00000000005f'
\set closedPriceWindowID '3a010000-0000-0000-0000-00000000005e'
\set closedReissueRequesterID '3a010000-0000-0000-0000-00000000005c'
\set closedTicketTypeID '3a010000-0000-0000-0000-00000000005d'
\set inProgressPriceWindowID '3a010000-0000-0000-0000-000000000054'
\set inProgressRequesterID '3a010000-0000-0000-0000-000000000055'
\set inProgressTicketTypeID '3a010000-0000-0000-0000-000000000056'
\set notYetOpenPriceWindowID '3a010000-0000-0000-0000-000000000062'
\set notYetOpenRequesterID '3a010000-0000-0000-0000-000000000060'
\set notYetOpenTicketTypeID '3a010000-0000-0000-0000-000000000061'
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
\set paidReadyGroupID '3a010000-0000-0000-0000-000000000064'
\set paidReadyPriceWindowID '3a010000-0000-0000-0000-000000000065'
\set paidReadyRequesterID '3a010000-0000-0000-0000-000000000066'
\set paidReadyTicketTypeID '3a010000-0000-0000-0000-000000000067'
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
\set requester13ID '3a010000-0000-0000-0000-000000000058'
\set unavailableTicketTypeID '3a010000-0000-0000-0000-00000000004b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'closedAcceptRequesterID');
select fx_user(:'closedReissueRequesterID');
select fx_user(:'notYetOpenRequesterID');
select fx_user(:'externalReadyRequesterID');
select fx_user(:'externalUnreadyRequesterID');
select fx_user(:'questionsAcceptedRequestUserID');
select fx_user(:'queuePriorityRequesterID');
select fx_user(:'queuePriorityWaitlistUserID');
select fx_user(:'soldOutOccupantID');
select fx_user(:'soldOutRequesterID');
select fx_user(:'expiredReservationOfferUserOneID');
select fx_user(:'expiredReservationOfferUserTwoID');
select fx_user(:'expiredReservationRequesterID');
select fx_user(:'expiredReservationWaitlistUserID');


-- Operator allowlist used by external approval readiness scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Community
insert into site (description, site_id, theme, title)
values (
    'Invitation request approval site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Invitation Request Approval Site'
);

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'General'));

-- Users
select fx_user(:'actorID', jsonb_build_object('username', 'actor'));

select fx_user(:'inProgressRequesterID', jsonb_build_object('username', 'in-progress'));

select fx_user(:'requesterID', jsonb_build_object('username', 'requester'));
select fx_user(:'requester2ID', jsonb_build_object('username', 'requester2'));
select fx_user(:'requester3ID', jsonb_build_object('username', 'requester3'));
select fx_user(:'requester4ID', jsonb_build_object('username', 'requester4'));
select fx_user(:'requester5ID', jsonb_build_object('username', 'requester5'));
select fx_user(:'requester6ID', jsonb_build_object('username', 'requester6'));
select fx_user(:'requester7ID', jsonb_build_object('username', 'requester7'));
select fx_user(:'requester8ID', jsonb_build_object('username', 'requester8'));
select fx_user(:'requester9ID', jsonb_build_object('username', 'requester9'));
select fx_user(:'requester10ID', jsonb_build_object('username', 'requester10'));
select fx_user(:'requester11ID', jsonb_build_object('username', 'requester11'));
select fx_user(:'requester12ID', jsonb_build_object('username', 'requester12'));
select fx_user(:'requester13ID', jsonb_build_object('username', 'requester13'));
select fx_user(:'paidReadyRequesterID', jsonb_build_object('username', 'paid-ready'));

-- Groups
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Group',
    'slug', 'group'
));
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Group with a payment recipient for successful paid approval snapshots
select fx_group(:'paidReadyGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{
        "provider": "stripe",
        "recipient_id": "acct_paid_ready",
        "seller_display_name": "Paid Ready Fiscal Sponsor"
    }'::jsonb));

-- Allowlisted group with external payments enabled for ready approvals
select fx_group(:'groupExternalReadyID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true
));

-- External-marked group outside the allowlist for approval rejection
select fx_group(:'groupExternalUnreadyID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US',
    'external_payments_enabled', true
));

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'capacity', 2,
    'description', 'd',
    'published', true
));
select fx_event(:'eventAttendanceCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'description', 'd',
    'published', true
));
select fx_event(:'eventFullID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'capacity', 1,
    'description', 'd',
    'published', true
));
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'description', 'd'
));
select fx_event(:'eventInactiveGroupID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'description', 'd',
    'published', true
));
select fx_event(:'eventApprovalDisabledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'd',
    'published', true
));
select fx_event(:'eventPastID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'description', 'd',
    'ends_at', current_timestamp - interval '1 hour',
    'published', true,
    'starts_at', current_timestamp - interval '2 hours'
));
select fx_event(:'eventPendingInvitationID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'description', 'd',
    'published', true
));
select fx_event(:'eventAttendeeConflictID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'description', 'd',
    'published', true
));
select fx_event(:'eventRegistrationOpenUntilStartID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'description', 'd',
    'ends_at', current_timestamp + interval '1 hour',
    'published', true,
    'registration_starts_at', current_timestamp - interval '2 hours',
    'starts_at', current_timestamp - interval '1 hour'
));

-- RSVP approval event whose expired reservations are swept before acceptance
select fx_event(:'eventExpiredReservationID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'capacity', 2,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Event with registration questions used to verify answer copying on accept
select fx_event(:'eventQuestionsApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'description', 'd',
    'published', true,
    'registration_questions', format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'registrationQuestionID'
    )::jsonb,
    'starts_at', '2030-01-02 10:00:00+00'
));

-- Ticketed approval events for tier assignment and capacity conflict scenarios
select fx_event(:'eventPrivateTicketApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'eventPublicTicketApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'eventQueuePriorityID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'eventTicketSoldOutID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'eventUnavailableTicketApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'eventReissueOfferBlockID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'eventReissuePurchaseBlockID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- In-progress ticketed approval event with a pending request
select fx_event(:'eventInProgressApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'ends_at', current_timestamp + interval '2 hours',
    'published', true,
    'registration_ends_at', current_timestamp - interval '1 hour',
    'registration_starts_at', current_timestamp - interval '2 hours',
    'starts_at', current_timestamp - interval '1 hour'
));

-- Approval event whose registration window has closed before start
select fx_event(:'eventRegistrationClosedApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'ends_at', current_timestamp + interval '4 hours',
    'published', true,
    'registration_ends_at', current_timestamp - interval '1 hour',
    'registration_starts_at', current_timestamp - interval '2 hours',
    'starts_at', current_timestamp + interval '2 hours'
));

-- Approval event whose public registration window has not opened yet
select fx_event(:'eventRegistrationNotYetOpenID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'ends_at', current_timestamp + interval '6 hours',
    'published', true,
    'registration_ends_at', current_timestamp + interval '3 hours',
    'registration_starts_at', current_timestamp + interval '1 hour',
    'starts_at', current_timestamp + interval '4 hours'
));

-- Paid ticket approval event with no payment recipient configured on the group
select fx_event(:'eventPaidNoRecipientApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Paid approval event with payment-ready venue context
select fx_event(:'eventPaidReadyApprovalID', :'paidReadyGroupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_zip_code', '97201'
));

-- External-marked approval event that is ready without Stripe
select fx_event(:'eventExternalReadyApprovalID', :'groupExternalReadyID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'external_payment_url', 'https://pay.example.test/accept-ready',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- External-marked approval event that is not allowlisted
select fx_event(:'eventExternalUnreadyApprovalID', :'groupExternalUnreadyID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'external_payment_url', 'https://pay.example.test/accept-unready',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'venue_address', '123 Main St',
    'venue_city', 'San Francisco',
    'venue_country_code', 'US',
    'venue_name', 'Community Hall',
    'venue_zip_code', '94105'
));

-- Ticket tiers assigned or checked by the approval workflows
select fx_event_ticket_type(:'inProgressTicketTypeID', :'eventInProgressApprovalID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'closedTicketTypeID', :'eventRegistrationClosedApprovalID', jsonb_build_object('seats_total', 2));
select fx_event_ticket_type(:'notYetOpenTicketTypeID', :'eventRegistrationNotYetOpenID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'privateTicketTypeID', :'eventPrivateTicketApprovalID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 1
));
select fx_event_ticket_type(:'publicAlternateTicketTypeID', :'eventPublicTicketApprovalID', jsonb_build_object(
    'order', 2,
    'seats_total', 2
));
select fx_event_ticket_type(:'publicGenericTicketTypeID', :'eventPrivateTicketApprovalID', jsonb_build_object(
    'order', 2,
    'seats_total', 1,
    'title', 'Generic public admission'
));
select fx_event_ticket_type(:'publicTicketTypeID', :'eventPublicTicketApprovalID', jsonb_build_object('seats_total', 2));
select fx_event_ticket_type(:'queuePriorityTicketTypeID', :'eventQueuePriorityID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'soldOutTicketTypeID', :'eventTicketSoldOutID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'unavailableTicketTypeID', :'eventUnavailableTicketApprovalID', jsonb_build_object(
    'active', false,
    'seats_total', 1
));
select fx_event_ticket_type(:'paidTicketTypeID', :'eventPaidNoRecipientApprovalID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'paidReadyTicketTypeID', :'eventPaidReadyApprovalID', jsonb_build_object(
    'seats_total', 1,
    'title', 'Paid ready admission'
));
select fx_event_ticket_type(:'externalReadyTicketTypeID', :'eventExternalReadyApprovalID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'externalUnreadyTicketTypeID', :'eventExternalUnreadyApprovalID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'reissueOfferBlockTicketTypeID', :'eventReissueOfferBlockID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'reissuePurchaseBlockTicketTypeID', :'eventReissuePurchaseBlockID', jsonb_build_object(
    'seats_total', 1,
    'title', 'Reissue purchase admission'
));

-- Current free prices for every ticket approval tier
select fx_event_ticket_price_window(:'closedPriceWindowID', :'closedTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'inProgressPriceWindowID', :'inProgressTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'notYetOpenPriceWindowID', :'notYetOpenTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'privateTicketPriceWindowID', :'privateTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'paidTicketPriceWindowID', :'paidTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'paidReadyPriceWindowID', :'paidReadyTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'externalReadyPriceWindowID', :'externalReadyTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'externalUnreadyPriceWindowID', :'externalUnreadyTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'publicAlternateTicketPriceWindowID', :'publicAlternateTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'publicGenericTicketPriceWindowID', :'publicGenericTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'publicTicketPriceWindowID', :'publicTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'reissueOfferBlockPriceWindowID', :'reissueOfferBlockTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'reissuePurchaseBlockPriceWindowID', :'reissuePurchaseBlockTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'queuePriorityPriceWindowID', :'queuePriorityTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'soldOutPriceWindowID', :'soldOutTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Events that do not exercise a named tier use a default free admission tier
select fx_event_ticket_type(
    gen_random_uuid(),
    e.event_id,
    jsonb_build_object(
        'seats_total', greatest(coalesce(e.capacity, 100), 1),
        'title', 'General Admission'
    )
)
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free prices for tiers without a named price fixture
select fx_event_ticket_price_window(
    gen_random_uuid(),
    ett.event_ticket_type_id,
    jsonb_build_object('amount_minor', 0)
)
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

-- Invitation requests
insert into event_invitation_request (event_id, event_ticket_type_id, user_id)
values
    (:'eventID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventID' limit 1), :'requesterID'),
    (:'eventID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventID' limit 1), :'requester2ID'),
    (:'eventFullID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventFullID' limit 1), :'requesterID'),
    (:'eventUnpublishedID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventUnpublishedID' limit 1), :'requesterID'),
    (:'eventInactiveGroupID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventInactiveGroupID' limit 1), :'requesterID'),
    (:'eventApprovalDisabledID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventApprovalDisabledID' limit 1), :'requesterID'),
    (:'eventPastID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventPastID' limit 1), :'requesterID'),
    (:'eventPendingInvitationID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventPendingInvitationID' limit 1), :'requester3ID'),
    (:'eventAttendeeConflictID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventAttendeeConflictID' limit 1), :'requester4ID'),
    (:'eventAttendeeConflictID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventAttendeeConflictID' limit 1), :'requester5ID'),
    (:'eventInProgressApprovalID', :'inProgressTicketTypeID', :'inProgressRequesterID'),
    (:'eventRegistrationClosedApprovalID', :'closedTicketTypeID', :'closedAcceptRequesterID'),
    (:'eventRegistrationNotYetOpenID', :'notYetOpenTicketTypeID', :'notYetOpenRequesterID'),
    (:'eventRegistrationOpenUntilStartID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventRegistrationOpenUntilStartID' limit 1), :'requester6ID'),
    (:'eventAttendanceCanceledID', (select event_ticket_type_id from event_ticket_type where event_id = :'eventAttendanceCanceledID' limit 1), :'requester7ID'),
    (:'eventPrivateTicketApprovalID', :'publicGenericTicketTypeID', :'requester3ID'),
    (:'eventPrivateTicketApprovalID', null, :'requester8ID'),
    (:'eventPrivateTicketApprovalID', null, :'requester13ID'),
    (:'eventPublicTicketApprovalID', :'publicTicketTypeID', :'requester4ID'),
    (:'eventUnavailableTicketApprovalID', :'unavailableTicketTypeID', :'requester9ID'),
    (:'eventPaidNoRecipientApprovalID', :'paidTicketTypeID', :'requester10ID'),
    (:'eventPaidReadyApprovalID', :'paidReadyTicketTypeID', :'paidReadyRequesterID'),
    (:'eventExternalReadyApprovalID', :'externalReadyTicketTypeID', :'externalReadyRequesterID'),
    (:'eventExternalUnreadyApprovalID', :'externalUnreadyTicketTypeID', :'externalUnreadyRequesterID'),
    (:'eventQueuePriorityID', :'queuePriorityTicketTypeID', :'queuePriorityRequesterID'),
    (:'eventTicketSoldOutID', :'soldOutTicketTypeID', :'soldOutRequesterID');

-- Pending RSVP request accepted after expired reservations are reconciled
insert into event_invitation_request (event_id, event_ticket_type_id, user_id)
values (
    :'eventExpiredReservationID',
    (select event_ticket_type_id from event_ticket_type where event_id = :'eventExpiredReservationID' limit 1),
    :'expiredReservationRequesterID'
);

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

-- Accepted request reissued after registration closes before start
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    reviewed_at,
    reviewed_by,
    status,
    user_id
) values (
    :'eventRegistrationClosedApprovalID',
    :'closedTicketTypeID',
    current_timestamp,
    :'actorID',
    'accepted',
    :'closedReissueRequesterID'
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
    0,
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
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values
    (
        :'expiredReservationOfferOneID',
        current_timestamp - interval '3 hours',
        :'eventExpiredReservationID',
        (select event_ticket_type_id from event_ticket_type where event_id = :'eventExpiredReservationID' limit 1),
        current_timestamp - interval '2 hours',
        'organizer_invitation',
        'pending',
        :'expiredReservationOfferUserOneID'
    ),
    (
        :'expiredReservationOfferTwoID',
        current_timestamp - interval '2 hours',
        :'eventExpiredReservationID',
        (select event_ticket_type_id from event_ticket_type where event_id = :'eventExpiredReservationID' limit 1),
        current_timestamp - interval '1 hour',
        'organizer_invitation',
        'pending',
        :'expiredReservationOfferUserTwoID'
    );

-- RSVP waitlist user promoted while expired reservations are swept
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'eventExpiredReservationID',
    (select event_ticket_type_id from event_ticket_type where event_id = :'eventExpiredReservationID' limit 1),
    :'expiredReservationWaitlistUserID'
);

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

-- Expired approval offer reissued after registration closes before start
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    organizer_user_id,
    source,
    status,
    user_id
) values (
    :'closedExpiredOfferID',
    current_timestamp - interval '2 hours',
    :'eventRegistrationClosedApprovalID',
    :'closedTicketTypeID',
    current_timestamp - interval '30 minutes',
    :'actorID',
    'approval',
    'expired',
    :'closedReissueRequesterID'
);

-- Invitation request with registration answers copied when accepted
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    user_id,
    registration_answers
)
values (
    :'eventQuestionsApprovalID',
    (select event_ticket_type_id from event_ticket_type where event_id = :'eventQuestionsApprovalID' limit 1),
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

-- Confirmed attendees own their tier capacity through completed purchases
insert into event_purchase (
    amount_minor,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
)
select
    0,
    0,
    ea.event_id,
    ett.event_ticket_type_id,
    'completed',
    ett.title,
    ea.user_id
from event_attendee ea
join lateral (
    select event_ticket_type_id, title
    from event_ticket_type
    where event_id = ea.event_id
    order by "order", event_ticket_type_id
    limit 1
) ett on true
where ea.status = 'confirmed';

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
    'OCG01',
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

-- Should derive the required tier when the organizer omits the redundant field
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,%L)',
        :'actorID',
        :'groupID',
        :'eventPrivateTicketApprovalID',
        :'requester3ID',
        'stripe'
    ),
    'Should derive the requested tier during approval'
);

-- Should create an offer for the request's persisted tier
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
    '{"offer_count":1,"request_status":"accepted"}'::jsonb,
    'Should accept the request and create its tier-scoped offer'
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
    'OCG01',
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

-- Should require a tier when accepting a generic private request
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,%L)',
        :'actorID',
        :'groupID',
        :'eventPrivateTicketApprovalID',
        :'requester13ID',
        'stripe'
    ),
    'OCG01',
    'invitation-only ticket type is required',
    'Should require a tier when accepting a generic private request'
);

-- Should reject a public tier assignment for a generic private request
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L)',
        :'actorID',
        :'groupID',
        :'eventPrivateTicketApprovalID',
        :'requester13ID',
        :'publicGenericTicketTypeID',
        'stripe'
    ),
    'OCG01',
    'ticket type is not available',
    'Should reject a public tier assignment for a generic private request'
);

-- Should assign an invitation-only tier to a generic private request
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L)',
        :'actorID',
        :'groupID',
        :'eventPrivateTicketApprovalID',
        :'requester8ID',
        :'privateTicketTypeID',
        'stripe'
    ),
    'Should assign an invitation-only tier to a generic private request'
);

-- Should create an offer for the assigned private tier
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
    '{"offer_count":1,"request_status":"accepted"}'::jsonb,
    'Should create an offer for the assigned private tier'
);

select is(
    (
        select (ntd.data->>'is_simple_rsvp')::boolean
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-ticket-request-approved'
        and n.user_id = :'requester8ID'::uuid
    ),
    false,
    'Should use ticket wording for an approved private-tier request'
);

-- Should reject duplicate approval while the first offer remains active
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
    'OCG01',
    'user already has an active admission offer for this event',
    'Should reject duplicate approval while its offer is active'
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
    'OCG01',
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
    'OCG01',
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

-- Should accept a paid request when the external event is ready
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,null)',
        :'actorID',
        :'groupExternalReadyID',
        :'eventExternalReadyApprovalID',
        :'externalReadyRequesterID'
    ),
    'Should accept a paid request when the external event is ready'
);

select is(
    (
        select count(*)::int
        from admission_offer
        where event_id = :'eventExternalReadyApprovalID'::uuid
        and user_id = :'externalReadyRequesterID'::uuid
        and status = 'pending'
    ),
    1,
    'Should create an offer when the external event is ready'
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
    'OCG01',
    'paid-capable events require a payment recipient',
    'Should reject paid approval when the group payment recipient is missing'
);

-- Should reject paid approval when an external-marked event is not ready
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,null)',
        :'actorID',
        :'groupExternalUnreadyID',
        :'eventExternalUnreadyApprovalID',
        :'externalUnreadyRequesterID'
    ),
    'OCG01',
    'external payments are not available for this event',
    'Should reject paid approval when an external-marked event is not ready'
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

-- Should reissue a reviewed ticket request after its previous offer is canceled
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
    accept_event_invitation_request(
        :'actorID',
        :'groupID',
        :'eventPublicTicketApprovalID',
        :'requester4ID',
        null,
        'stripe'
    )->>'outcome',
    'offer-created',
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

-- Should reject changing the persisted tier during a later approval attempt
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L)',
        :'actorID',
        :'groupID',
        :'eventPrivateTicketApprovalID',
        :'requester3ID',
        :'privateTicketTypeID',
        'stripe'
    ),
    'OCG01',
    'requested ticket type cannot be changed',
    'Should reject changing the persisted request tier'
);

-- Should retain the original request-tier offer
select is(
    (
        select jsonb_build_array(ao.source, ao.status, ao.event_ticket_type_id)
        from admission_offer ao
        where ao.event_id = :'eventPrivateTicketApprovalID'::uuid
        and ao.user_id = :'requester3ID'::uuid
    ),
    format('["approval","pending","%s"]', :'publicGenericTicketTypeID')::jsonb,
    'Should retain the original request-tier approval offer'
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
            'event_ticket_type_id', :'publicGenericTicketTypeID',
            'is_simple_rsvp', true,
            'theme', jsonb_build_object('primary_color', '#2563eb'),
            'ticket_title', 'Generic public admission',
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
    '{"conflict":"queue-has-priority"}'::jsonb,
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
    '{"conflict":"ticket-type-sold-out"}'::jsonb,
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

-- Should preserve canceled attendance history while creating an offer
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventAttendanceCanceledID', :'requester7ID'
    ),
    'Should accept a request with canceled attendance history'
);

-- Should leave canceled attendance metadata unchanged
select results_eq(
    format($$
        select
            attendance_canceled_at is not null,
            attendance_canceled_by_user_id,
            status
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventAttendanceCanceledID', :'requester7ID'),
    format(
        $$ values (true, %L::uuid, 'attendance-canceled'::text) $$,
        :'requester7ID'
    ),
    'Should preserve canceled attendance metadata'
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

-- Should reserve approval through an offer without creating attendance
select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'requesterID'::uuid
    ) and exists (
        select 1
        from admission_offer
        where event_id = :'eventID'::uuid
        and user_id = :'requesterID'::uuid
        and status = 'pending'
    ),
    'Should create an approval offer without confirming attendance'
);

-- Should persist a free issue-time price snapshot on the approval offer
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
        :'eventID',
        :'requesterID'
    ),
    $$ values (
        0::bigint,
        null::text,
        0::bigint,
        null::text,
        null::uuid,
        'General Admission'::text
    ) $$,
    'Should persist a free issue-time price snapshot on the approval offer'
);

-- Should accept a paid-ready invitation request
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid,null,%L)',
        :'actorID',
        :'paidReadyGroupID',
        :'eventPaidReadyApprovalID',
        :'paidReadyRequesterID',
        'stripe'
    ),
    'Should accept a paid-ready invitation request'
);

-- Should persist a paid issue-time price snapshot on the approval offer
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
        :'eventPaidReadyApprovalID',
        :'paidReadyRequesterID'
    ),
    $$ values (
        2500::bigint,
        'USD'::text,
        0::bigint,
        null::text,
        null::uuid,
        'Paid ready admission'::text
    ) $$,
    'Should persist a paid issue-time price snapshot on the approval offer'
);

-- Should accept after reconciling expired reservations
select is(
    accept_event_invitation_request(
        :'actorID',
        :'groupID',
        :'eventExpiredReservationID',
        :'expiredReservationRequesterID'
    )->>'outcome',
    'offer-created',
    'Should accept after reconciling expired reservations'
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
                select ao.status
                from admission_offer ao
                where ao.event_id = :'eventExpiredReservationID'::uuid
                and ao.user_id = :'expiredReservationWaitlistUserID'::uuid
            ),
            'request_status', (
                select eir.status
                from event_invitation_request eir
                where eir.event_id = :'eventExpiredReservationID'::uuid
                and eir.user_id = :'expiredReservationRequesterID'::uuid
            )
        )
    ),
    '{"offer_statuses":["expired","expired"],"promoted_status":"pending","request_status":"accepted"}'::jsonb,
    'Should persist expired reservation reconciliation before accepting'
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
    $$ values ('invitation-canceled'::text, false) $$,
    'Should preserve canceled invitation history'
);

-- Should track the acceptance in the audit log
select results_eq(
    format(
        $$
        select
            action,
            actor_user_id,
            community_id,
            details - 'admission_offer_id' - 'event_ticket_type_id',
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

-- Should report a sold-out tier without reviewing the request
select is(
    accept_event_invitation_request(
        :'actorID',
        :'groupID',
        :'eventFullID',
        :'requesterID'
    ),
    '{"conflict":"ticket-type-sold-out"}'::jsonb,
    'Should report a sold-out tier when capacity is full'
);

-- Should reject accepting when event is unpublished
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventUnpublishedID', :'requesterID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject accepting when event is unpublished'
);

-- Should reject accepting when event belongs to an inactive group
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'inactiveGroupID', :'eventInactiveGroupID', :'requesterID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject accepting when event belongs to an inactive group'
);

-- Should reject accepting when event approval is disabled
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventApprovalDisabledID', :'requesterID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject accepting when event approval is disabled'
);

-- Should reject accepting when event is past
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventPastID', :'requesterID'
    ),
    'OCG01',
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

-- Should accept invitation requests after registration closes before the event starts
select is(
    accept_event_invitation_request(
        :'actorID',
        :'groupID',
        :'eventRegistrationClosedApprovalID',
        :'closedAcceptRequesterID'
    )->>'outcome',
    'offer-created',
    'Should accept invitation requests after registration closes before the event starts'
);

-- Should bound post-close approval offers by the remaining event window
select results_eq(
    format(
        $$
            select
                ao.expires_at
                    = least(current_timestamp + interval '24 hours', e.starts_at),
                ao.expires_at > e.registration_ends_at,
                ao.status,
                eir.status
            from admission_offer ao
            join event e using (event_id)
            join event_invitation_request eir
                on eir.event_id = ao.event_id
                and eir.user_id = ao.user_id
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
            and ao.status = 'pending'
        $$,
        :'eventRegistrationClosedApprovalID',
        :'closedAcceptRequesterID'
    ),
    $$ values (true, true, 'pending'::text, 'accepted'::text) $$,
    'Should bound post-close approval offers by the remaining event window'
);

-- Should reissue expired approval offers after registration closes before the event starts
select is(
    accept_event_invitation_request(
        :'actorID',
        :'groupID',
        :'eventRegistrationClosedApprovalID',
        :'closedReissueRequesterID'
    )->>'outcome',
    'offer-created',
    'Should reissue expired approval offers after registration closes before the event starts'
);

-- Should keep the expired offer and bound the reissued offer by event start
select is(
    (
        select jsonb_build_object(
            'expired_count', count(*) filter (where ao.status = 'expired'),
            'expires_at_matches', bool_or(
                ao.status = 'pending'
                and ao.expires_at
                    = least(current_timestamp + interval '24 hours', e.starts_at)
                and ao.expires_at > e.registration_ends_at
            ),
            'pending_count', count(*) filter (where ao.status = 'pending')
        )
        from admission_offer ao
        join event e using (event_id)
        where ao.event_id = :'eventRegistrationClosedApprovalID'::uuid
        and ao.user_id = :'closedReissueRequesterID'::uuid
    ),
    '{"expired_count": 1, "expires_at_matches": true, "pending_count": 1}'::jsonb,
    'Should keep the expired offer and bound the reissued offer by event start'
);

-- Should accept invitation requests before registration opens
select is(
    accept_event_invitation_request(
        :'actorID',
        :'groupID',
        :'eventRegistrationNotYetOpenID',
        :'notYetOpenRequesterID'
    )->>'outcome',
    'offer-created',
    'Should accept invitation requests before registration opens'
);

-- Should create a pending offer when accepting before registration opens
select results_eq(
    format(
        $$
            select ao.status, eir.status
            from admission_offer ao
            join event_invitation_request eir
                on eir.event_id = ao.event_id
                and eir.user_id = ao.user_id
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
            and ao.status = 'pending'
        $$,
        :'eventRegistrationNotYetOpenID',
        :'notYetOpenRequesterID'
    ),
    $$ values ('pending'::text, 'accepted'::text) $$,
    'Should create a pending offer when accepting before registration opens'
);

-- Should reject accepting an already reviewed request
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requesterID'
    ),
    'OCG01',
    'user already has an active admission offer for this event',
    'Should reject accepting an already reviewed request'
);

-- Should reject accepting when the requester is already attending
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventAttendeeConflictID', :'requester4ID'
    ),
    'OCG01',
    'user already has active attendance for this event',
    'Should reject accepting when the requester is already attending'
);

-- Should allow a new request after a rejected organizer invitation
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventAttendeeConflictID', :'requester5ID'
    ),
    'Should accept a new request after a rejected organizer invitation'
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
    '{"attendee_statuses": ["confirmed", "invitation-rejected"], "request_statuses": ["pending", "accepted"]}'::jsonb,
    'Should leave attendance history unchanged while reviewing eligible requests'
);

-- Should accept invitation requests that include registration answers
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventQuestionsApprovalID', :'questionsAcceptedRequestUserID'
    ),
    'Should accept invitation requests that include registration answers'
);

-- Should retain request answers for the later checkout claim
select is(
    (
        select registration_answers
        from event_invitation_request
        where event_id = :'eventQuestionsApprovalID'::uuid
        and user_id = :'questionsAcceptedRequestUserID'::uuid
    ),
    format(
        '{"answers": [{"question_id": "%s", "value": "Accepted request answer"}]}',
        :'registrationQuestionID'
    )::jsonb,
    'Should retain request answers for checkout'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
