-- Tests routing event attendance into checkout, approval, or a ticket waitlist.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(59);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeApprovalOfferID '5e020000-0000-0000-0000-00000000003c'
\set activeApprovalOfferUserID '5e020000-0000-0000-0000-00000000003d'
\set activeApprovalPurchaseID '5e020000-0000-0000-0000-00000000003e'
\set activeApprovalPurchaseUserID '5e020000-0000-0000-0000-00000000003f'
\set communityID '5e020000-0000-0000-0000-000000000001'
\set duplicateWaitlistUserID '5e020000-0000-0000-0000-000000000055'
\set eventCanceledHistoryID '5e020000-0000-0000-0000-00000000002b'
\set eventCategoryID '5e020000-0000-0000-0000-000000000003'
\set eventFullNoWaitlistID '5e020000-0000-0000-0000-000000000005'
\set eventFullWaitlistID '5e020000-0000-0000-0000-000000000006'
\set eventInviteOnlyID '5e020000-0000-0000-0000-000000000008'
\set eventOKID '5e020000-0000-0000-0000-000000000009'
\set eventQuestionsApprovalID '5e020000-0000-0000-0000-00000000000b'
\set eventQuestionsFullWaitlistID '5e020000-0000-0000-0000-00000000000c'
\set eventQuestionsID '5e020000-0000-0000-0000-00000000000d'
\set eventRegistrationClosedID '5e020000-0000-0000-0000-000000000025'
\set eventSimpleRsvpBlockedHoldID '5e020000-0000-0000-0000-000000000078'
\set eventSimpleRsvpHoldID '5e020000-0000-0000-0000-000000000073'
\set eventTicketApprovalID '5e020000-0000-0000-0000-000000000036'
\set eventTicketAvailableID '5e020000-0000-0000-0000-000000000040'
\set eventTicketedID '5e020000-0000-0000-0000-00000000002d'
\set eventTicketPrivateApprovalID '5e020000-0000-0000-0000-000000000037'
\set eventTicketPrivateSelectionID '5e020000-0000-0000-0000-000000000041'
\set eventTicketSoldOutNoWaitlistID '5e020000-0000-0000-0000-000000000042'
\set eventTicketUnavailableID '5e020000-0000-0000-0000-000000000057'
\set eventTicketWaitlistActivePurchaseID '5e020000-0000-0000-0000-000000000043'
\set eventUnpublishedID '5e020000-0000-0000-0000-00000000000e'
\set groupCategoryID '5e020000-0000-0000-0000-00000000000f'
\set groupID '5e020000-0000-0000-0000-000000000010'
\set ignoredQuestionID '5e020000-0000-0000-0000-000000000011'
\set questionID '5e020000-0000-0000-0000-000000000013'
\set questionsAttendeeUserID '5e020000-0000-0000-0000-000000000014'
\set questionsCommunityID '5e020000-0000-0000-0000-000000000015'
\set questionsEventCategoryID '5e020000-0000-0000-0000-000000000016'
\set questionsGroupCategoryID '5e020000-0000-0000-0000-000000000017'
\set questionsGroupID '5e020000-0000-0000-0000-000000000018'
\set questionsMissingAnswersUserID '5e020000-0000-0000-0000-000000000056'
\set questionsRequestUserID '5e020000-0000-0000-0000-00000000001c'
\set questionsSeatUserID '5e020000-0000-0000-0000-00000000001d'
\set questionsWaitlistUserID '5e020000-0000-0000-0000-00000000001e'
\set ticketApprovalPriceWindowID '5e020000-0000-0000-0000-000000000038'
\set ticketApprovalTypeID '5e020000-0000-0000-0000-000000000039'
\set ticketAvailablePriceWindowID '5e020000-0000-0000-0000-000000000044'
\set ticketAvailableTypeID '5e020000-0000-0000-0000-000000000045'
\set ticketAvailableUserID '5e020000-0000-0000-0000-000000000046'
\set ticketCanceledHistoryPriceWindowID '5e020000-0000-0000-0000-00000000005e'
\set ticketCanceledHistoryTypeID '5e020000-0000-0000-0000-00000000005f'
\set ticketExpiredPurchaseID '5e020000-0000-0000-0000-000000000053'
\set ticketExpiredPurchaseUserID '5e020000-0000-0000-0000-000000000054'
\set ticketFullNoWaitlistHolderPurchaseID '5e020000-0000-0000-0000-000000000070'
\set ticketFullNoWaitlistPriceWindowID '5e020000-0000-0000-0000-00000000005c'
\set ticketFullNoWaitlistTypeID '5e020000-0000-0000-0000-00000000005d'
\set ticketFullWaitlistHolderPurchaseID '5e020000-0000-0000-0000-000000000071'
\set ticketFullWaitlistPriceWindowID '5e020000-0000-0000-0000-000000000060'
\set ticketFullWaitlistTypeID '5e020000-0000-0000-0000-000000000061'
\set ticketInactivePriceWindowID '5e020000-0000-0000-0000-000000000058'
\set ticketInactiveTypeID '5e020000-0000-0000-0000-000000000059'
\set ticketInviteOnlyPriceWindowID '5e020000-0000-0000-0000-000000000062'
\set ticketInviteOnlyTypeID '5e020000-0000-0000-0000-000000000063'
\set ticketOKPriceWindowID '5e020000-0000-0000-0000-000000000064'
\set ticketOKTypeID '5e020000-0000-0000-0000-000000000065'
\set ticketPendingPurchaseID '5e020000-0000-0000-0000-000000000030'
\set ticketPriceWindowID '5e020000-0000-0000-0000-00000000002f'
\set ticketPrivateApprovalPriceWindowID '5e020000-0000-0000-0000-00000000003a'
\set ticketPrivateApprovalTypeID '5e020000-0000-0000-0000-00000000003b'
\set ticketPrivateSelectionPriceWindowID '5e020000-0000-0000-0000-000000000047'
\set ticketPrivateSelectionTypeID '5e020000-0000-0000-0000-000000000048'
\set ticketPrivateSelectionUserID '5e020000-0000-0000-0000-000000000049'
\set ticketQuestionsApprovalPriceWindowID '5e020000-0000-0000-0000-000000000068'
\set ticketQuestionsApprovalTypeID '5e020000-0000-0000-0000-000000000069'
\set ticketQuestionsFullWaitlistPriceWindowID '5e020000-0000-0000-0000-00000000006a'
\set ticketQuestionsFullWaitlistTypeID '5e020000-0000-0000-0000-00000000006b'
\set ticketQuestionsPriceWindowID '5e020000-0000-0000-0000-000000000066'
\set ticketQuestionsSeatPurchaseID '5e020000-0000-0000-0000-000000000072'
\set ticketQuestionsTypeID '5e020000-0000-0000-0000-000000000067'
\set ticketRegistrationClosedPriceWindowID '5e020000-0000-0000-0000-00000000006c'
\set ticketRegistrationClosedTypeID '5e020000-0000-0000-0000-00000000006d'
\set ticketSecondHolderPurchaseID '5e020000-0000-0000-0000-000000000033'
\set ticketSecondPriceWindowID '5e020000-0000-0000-0000-000000000034'
\set ticketSecondTypeID '5e020000-0000-0000-0000-000000000035'
\set ticketSimpleRsvpBlockedHoldPrivatePriceWindowID '5e020000-0000-0000-0000-000000000079'
\set ticketSimpleRsvpBlockedHoldPrivateTypeID '5e020000-0000-0000-0000-00000000007a'
\set ticketSimpleRsvpBlockedHoldPublicPriceWindowID '5e020000-0000-0000-0000-00000000007b'
\set ticketSimpleRsvpBlockedHoldPublicTypeID '5e020000-0000-0000-0000-00000000007c'
\set ticketSimpleRsvpBlockedHoldPurchaseID '5e020000-0000-0000-0000-00000000007d'
\set ticketSimpleRsvpBlockedHoldUserID '5e020000-0000-0000-0000-00000000007e'
\set ticketSimpleRsvpHoldPriceWindowID '5e020000-0000-0000-0000-000000000074'
\set ticketSimpleRsvpHoldPurchaseID '5e020000-0000-0000-0000-000000000075'
\set ticketSimpleRsvpHoldTypeID '5e020000-0000-0000-0000-000000000076'
\set ticketSimpleRsvpHoldUserID '5e020000-0000-0000-0000-000000000077'
\set ticketSoldOutNoWaitlistHolderPurchaseID '5e020000-0000-0000-0000-00000000004a'
\set ticketSoldOutNoWaitlistHolderUserID '5e020000-0000-0000-0000-00000000004b'
\set ticketSoldOutNoWaitlistPriceWindowID '5e020000-0000-0000-0000-00000000004c'
\set ticketSoldOutNoWaitlistTypeID '5e020000-0000-0000-0000-00000000004d'
\set ticketSoldOutNoWaitlistUserID '5e020000-0000-0000-0000-00000000004e'
\set ticketTypeID '5e020000-0000-0000-0000-00000000002e'
\set ticketUnpublishedPriceWindowID '5e020000-0000-0000-0000-00000000006e'
\set ticketUnpublishedTypeID '5e020000-0000-0000-0000-00000000006f'
\set ticketUpcomingPriceWindowID '5e020000-0000-0000-0000-00000000005a'
\set ticketUpcomingTypeID '5e020000-0000-0000-0000-00000000005b'
\set ticketWaitlistActivePurchaseID '5e020000-0000-0000-0000-00000000004f'
\set ticketWaitlistActivePurchasePriceWindowID '5e020000-0000-0000-0000-000000000050'
\set ticketWaitlistActivePurchaseTypeID '5e020000-0000-0000-0000-000000000051'
\set ticketWaitlistActivePurchaseUserID '5e020000-0000-0000-0000-000000000052'
\set user1ID '5e020000-0000-0000-0000-00000000001f'
\set user2ID '5e020000-0000-0000-0000-000000000020'
\set user3ID '5e020000-0000-0000-0000-000000000021'
\set user4ID '5e020000-0000-0000-0000-000000000022'
\set user6ID '5e020000-0000-0000-0000-000000000024'
\set user7ID '5e020000-0000-0000-0000-000000000027'
\set user10ID '5e020000-0000-0000-0000-00000000002c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the main group
select fx_community(:'communityID');

-- Community hosting the registration questions group
select fx_community(:'questionsCommunityID');

-- User holding an active offer on the public-tier approval event
select fx_user(:'activeApprovalOfferUserID');

-- User holding an active purchase on the public-tier approval event
select fx_user(:'activeApprovalPurchaseUserID');

-- User already queued for the first ticketed tier
select fx_user(:'duplicateWaitlistUserID');

-- Named user routed into checkout on the registration questions event
select fx_user(:'questionsAttendeeUserID', jsonb_build_object('name', 'Attendee'));

-- User requesting approval without registration answers
select fx_user(:'questionsMissingAnswersUserID');

-- User requesting approval with registration answers
select fx_user(:'questionsRequestUserID');

-- User holding the only seat on the full registration questions event
select fx_user(:'questionsSeatUserID');

-- User joining the full registration questions event waitlist
select fx_user(:'questionsWaitlistUserID');

-- User routed into checkout on the available tier
select fx_user(:'ticketAvailableUserID');

-- User retrying after an expired free checkout hold
select fx_user(:'ticketExpiredPurchaseUserID');

-- User requesting approval on the fully private event
select fx_user(:'ticketPrivateSelectionUserID');

-- User holding a live invitation-only checkout hold on the simple RSVP event
select fx_user(:'ticketSimpleRsvpBlockedHoldUserID');

-- User holding a live free checkout hold on the simple RSVP event
select fx_user(:'ticketSimpleRsvpHoldUserID');

-- User holding the only seat on the sold-out no-waitlist tier
select fx_user(:'ticketSoldOutNoWaitlistHolderUserID');

-- User rejected by the sold-out no-waitlist tier
select fx_user(:'ticketSoldOutNoWaitlistUserID');

-- User holding a live free checkout on the active-purchase waitlist tier
select fx_user(:'ticketWaitlistActivePurchaseUserID');

-- User confirmed on the full events and reviewing invitation requests
select fx_user(:'user1ID');

-- User joining waitlists and requesting approval
select fx_user(:'user2ID');

-- User with canceled organizer invitations and an accepted request
select fx_user(:'user3ID');

-- User with canceled attendance and a rejected request
select fx_user(:'user4ID');

-- User with a rejected organizer invitation
select fx_user(:'user6ID');

-- User with canceled attendance on the full no-waitlist event
select fx_user(:'user7ID');

-- User with canceled attendance history and a live ticketed checkout
select fx_user(:'user10ID');

-- Event category in the main community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Event category in the registration questions community
select fx_event_category(:'questionsEventCategoryID', :'questionsCommunityID');

-- Group category in the main community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category in the registration questions community
select fx_group_category(:'questionsGroupCategoryID', :'questionsCommunityID');

-- Group hosting the main events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group hosting the registration questions events
select fx_group(:'questionsGroupID', :'questionsCommunityID', :'questionsGroupCategoryID');

-- Published event with canceled attendance history
select fx_event(:'eventCanceledHistoryID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Canceled history',
    'published', true
));

-- Published full event without a waitlist
select fx_event(:'eventFullNoWaitlistID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Published full event with a waitlist
select fx_event(:'eventFullWaitlistID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'waitlist_enabled', true
));

-- Published approval-required event with earlier invitation request decisions
select fx_event(:'eventInviteOnlyID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));

-- Published event with free capacity
select fx_event(:'eventOKID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'OK',
    'published', true,
    'slug', 'ok'
));

-- Published approval-required event collecting registration answers
select fx_event(:'eventQuestionsApprovalID', :'questionsGroupID', :'questionsEventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true,
    'registration_questions', format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    'starts_at', '2030-01-02 10:00:00+00'
));

-- Published full event with a waitlist collecting registration answers
select fx_event(:'eventQuestionsFullWaitlistID', :'questionsGroupID', :'questionsEventCategoryID', jsonb_build_object(
    'published', true,
    'registration_questions', format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    'starts_at', '2030-01-03 10:00:00+00',
    'waitlist_enabled', true
));

-- Published event collecting registration answers
select fx_event(:'eventQuestionsID', :'questionsGroupID', :'questionsEventCategoryID', jsonb_build_object(
    'published', true,
    'registration_questions', format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    'starts_at', '2030-01-01 10:00:00+00'
));

-- Published event whose registration window already closed
select fx_event(:'eventRegistrationClosedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'registration_ends_at', current_timestamp - interval '1 hour',
    'starts_at', '2030-01-04 10:00:00+00'
));

-- Published simple RSVP event with a live checkout hold on its invitation-only tier
select fx_event(:'eventSimpleRsvpBlockedHoldID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Published simple RSVP event without a waitlist and with a live free checkout hold
select fx_event(:'eventSimpleRsvpHoldID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Published approval-required event with one public tier
select fx_event(:'eventTicketApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));

-- Published event with a tier that still has seats
select fx_event(:'eventTicketAvailableID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'waitlist_enabled', true
));

-- Published ticketed event with two sold-out public tiers and a waitlist
select fx_event(:'eventTicketedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Ticketed',
    'published', true,
    'waitlist_enabled', true
));

-- Published approval-required event selected with another event's public tier
select fx_event(:'eventTicketPrivateApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));

-- Published approval-required event whose only tier is invitation-only
select fx_event(:'eventTicketPrivateSelectionID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));

-- Published event with a sold-out tier and no waitlist
select fx_event(:'eventTicketSoldOutNoWaitlistID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Published event whose public tiers are inactive or not yet priced
select fx_event(:'eventTicketUnavailableID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Published event whose single seat is held by a live free checkout
select fx_event(:'eventTicketWaitlistActivePurchaseID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'waitlist_enabled', true
));

-- Unpublished event hidden from attendees
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Unpublished',
    'slug', 'unpublished'
));

-- Confirmed attendees holding the seats of the full events
insert into event_attendee (event_id, user_id, status)
values
    (:'eventFullNoWaitlistID', :'user1ID', 'confirmed'),
    (:'eventFullWaitlistID', :'user1ID', 'confirmed'),
    (:'eventQuestionsFullWaitlistID', :'questionsSeatUserID', 'confirmed');

-- Canceled attendees exercising capacity checks during a new RSVP
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values
    (current_timestamp, :'user1ID', :'eventFullNoWaitlistID', 'attendance-canceled', :'user7ID'),
    (current_timestamp, :'user1ID', :'eventFullWaitlistID', 'attendance-canceled', :'user4ID');

-- Canceled attendee history kept while a new RSVP routes into checkout
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values (
    '2001-01-01 00:00:00+00',
    :'user7ID',
    :'eventCanceledHistoryID',
    'attendance-canceled',
    :'user10ID'
);

-- Existing organizer invitation decisions
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'eventOKID', :'user3ID', true, 'invitation-canceled'),
    (:'eventFullWaitlistID', :'user3ID', false, 'invitation-canceled'),
    (:'eventFullNoWaitlistID', :'user6ID', true, 'invitation-rejected');

-- Public tier with seats on the approval-required event
select fx_event_ticket_type(:'ticketApprovalTypeID', :'eventTicketApprovalID', jsonb_build_object('seats_total', 10));

-- Two-seat tier with seats left for checkout
select fx_event_ticket_type(:'ticketAvailableTypeID', :'eventTicketAvailableID', jsonb_build_object('seats_total', 2));

-- Ten-seat tier on the canceled history event
select fx_event_ticket_type(:'ticketCanceledHistoryTypeID', :'eventCanceledHistoryID', jsonb_build_object('seats_total', 10));

-- Single-seat tier already sold out to the confirmed no-waitlist attendee
select fx_event_ticket_type(:'ticketFullNoWaitlistTypeID', :'eventFullNoWaitlistID', jsonb_build_object('seats_total', 1, 'title', 'General Admission'));

-- Single-seat tier already sold out to the confirmed waitlist event attendee
select fx_event_ticket_type(:'ticketFullWaitlistTypeID', :'eventFullWaitlistID', jsonb_build_object('seats_total', 1, 'title', 'General Admission'));

-- Inactive public tier that attendees cannot select
select fx_event_ticket_type(:'ticketInactiveTypeID', :'eventTicketUnavailableID', jsonb_build_object('active', false));

-- Single-seat tier on the approval-required event with request decisions
select fx_event_ticket_type(:'ticketInviteOnlyTypeID', :'eventInviteOnlyID', jsonb_build_object('seats_total', 1));

-- Ten-seat tier on the free capacity event
select fx_event_ticket_type(:'ticketOKTypeID', :'eventOKID', jsonb_build_object('seats_total', 10));

-- Invitation-only tier leaving the private approval event without public tiers
select fx_event_ticket_type(:'ticketPrivateApprovalTypeID', :'eventTicketPrivateApprovalID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 10
));

-- Invitation-only tier on the fully private event
select fx_event_ticket_type(:'ticketPrivateSelectionTypeID', :'eventTicketPrivateSelectionID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 10
));

-- Ten-seat tier on the approval-required registration questions event
select fx_event_ticket_type(:'ticketQuestionsApprovalTypeID', :'eventQuestionsApprovalID', jsonb_build_object('seats_total', 10));

-- Single-seat tier already sold out on the full registration questions event
select fx_event_ticket_type(:'ticketQuestionsFullWaitlistTypeID', :'eventQuestionsFullWaitlistID', jsonb_build_object('seats_total', 1, 'title', 'General Admission'));

-- Ten-seat tier on the registration questions event
select fx_event_ticket_type(:'ticketQuestionsTypeID', :'eventQuestionsID', jsonb_build_object('seats_total', 10));

-- Ten-seat tier on the closed registration event
select fx_event_ticket_type(:'ticketRegistrationClosedTypeID', :'eventRegistrationClosedID', jsonb_build_object('seats_total', 10));

-- Second sold-out public tier on the ticketed event
select fx_event_ticket_type(:'ticketSecondTypeID', :'eventTicketedID', jsonb_build_object(
    'order', 2,
    'seats_total', 1
));

-- Invitation-only tier holding the live checkout on the blocked simple RSVP event
select fx_event_ticket_type(:'ticketSimpleRsvpBlockedHoldPrivateTypeID', :'eventSimpleRsvpBlockedHoldID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 10
));

-- Sole public tier on the blocked simple RSVP event
select fx_event_ticket_type(:'ticketSimpleRsvpBlockedHoldPublicTypeID', :'eventSimpleRsvpBlockedHoldID', jsonb_build_object('seats_total', 10));

-- Sole public tier whose single seat is held by the live free checkout
select fx_event_ticket_type(:'ticketSimpleRsvpHoldTypeID', :'eventSimpleRsvpHoldID', jsonb_build_object('seats_total', 1));

-- Single-seat tier sold out on the no-waitlist event
select fx_event_ticket_type(:'ticketSoldOutNoWaitlistTypeID', :'eventTicketSoldOutNoWaitlistID', jsonb_build_object('seats_total', 1));

-- First sold-out public tier on the ticketed event
select fx_event_ticket_type(:'ticketTypeID', :'eventTicketedID', jsonb_build_object('seats_total', 1));

-- Ten-seat tier on the unpublished event
select fx_event_ticket_type(:'ticketUnpublishedTypeID', :'eventUnpublishedID', jsonb_build_object('seats_total', 10));

-- Public tier priced only in the future, so attendees cannot select it
select fx_event_ticket_type(:'ticketUpcomingTypeID', :'eventTicketUnavailableID', jsonb_build_object('order', 2));

-- Single-seat tier held by a live free checkout
select fx_event_ticket_type(:'ticketWaitlistActivePurchaseTypeID', :'eventTicketWaitlistActivePurchaseID', jsonb_build_object('seats_total', 1));

-- Active ticket offer that blocks a duplicate approval request
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'activeApprovalOfferID',
    :'eventTicketApprovalID',
    :'ticketApprovalTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'activeApprovalOfferUserID'
);

-- Event invitation requests
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    user_id,
    created_at,
    status,
    reviewed_at,
    reviewed_by
)
values
    (
        :'eventInviteOnlyID',
        :'ticketInviteOnlyTypeID',
        :'user3ID',
        '2024-01-01 00:00:00+00',
        'accepted',
        '2024-01-01 01:00:00+00',
        :'user1ID'
    ),
    (
        :'eventInviteOnlyID',
        :'ticketInviteOnlyTypeID',
        :'user4ID',
        '2024-01-02 00:00:00+00',
        'rejected',
        '2024-01-02 01:00:00+00',
        :'user1ID'
    );

-- Current free price for the public approval tier
select fx_event_ticket_price_window(:'ticketApprovalPriceWindowID', :'ticketApprovalTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the available tier
select fx_event_ticket_price_window(:'ticketAvailablePriceWindowID', :'ticketAvailableTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the canceled history tier
select fx_event_ticket_price_window(:'ticketCanceledHistoryPriceWindowID', :'ticketCanceledHistoryTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the full no-waitlist tier
select fx_event_ticket_price_window(:'ticketFullNoWaitlistPriceWindowID', :'ticketFullNoWaitlistTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the full waitlist tier
select fx_event_ticket_price_window(:'ticketFullWaitlistPriceWindowID', :'ticketFullWaitlistTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the inactive tier
select fx_event_ticket_price_window(:'ticketInactivePriceWindowID', :'ticketInactiveTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the request decisions tier
select fx_event_ticket_price_window(:'ticketInviteOnlyPriceWindowID', :'ticketInviteOnlyTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the free capacity tier
select fx_event_ticket_price_window(:'ticketOKPriceWindowID', :'ticketOKTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the private approval tier
select fx_event_ticket_price_window(:'ticketPrivateApprovalPriceWindowID', :'ticketPrivateApprovalTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the fully private tier
select fx_event_ticket_price_window(:'ticketPrivateSelectionPriceWindowID', :'ticketPrivateSelectionTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the approval-required registration questions tier
select fx_event_ticket_price_window(:'ticketQuestionsApprovalPriceWindowID', :'ticketQuestionsApprovalTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the full registration questions tier
select fx_event_ticket_price_window(:'ticketQuestionsFullWaitlistPriceWindowID', :'ticketQuestionsFullWaitlistTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the registration questions tier
select fx_event_ticket_price_window(:'ticketQuestionsPriceWindowID', :'ticketQuestionsTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the closed registration tier
select fx_event_ticket_price_window(:'ticketRegistrationClosedPriceWindowID', :'ticketRegistrationClosedTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the second ticketed tier
select fx_event_ticket_price_window(:'ticketSecondPriceWindowID', :'ticketSecondTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the blocked simple RSVP invitation-only tier
select fx_event_ticket_price_window(:'ticketSimpleRsvpBlockedHoldPrivatePriceWindowID', :'ticketSimpleRsvpBlockedHoldPrivateTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the blocked simple RSVP public tier
select fx_event_ticket_price_window(:'ticketSimpleRsvpBlockedHoldPublicPriceWindowID', :'ticketSimpleRsvpBlockedHoldPublicTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the simple RSVP tier
select fx_event_ticket_price_window(:'ticketSimpleRsvpHoldPriceWindowID', :'ticketSimpleRsvpHoldTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the sold-out no-waitlist tier
select fx_event_ticket_price_window(:'ticketSoldOutNoWaitlistPriceWindowID', :'ticketSoldOutNoWaitlistTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the first ticketed tier
select fx_event_ticket_price_window(:'ticketPriceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 0));

-- Current free price for the unpublished event tier
select fx_event_ticket_price_window(:'ticketUnpublishedPriceWindowID', :'ticketUnpublishedTypeID', jsonb_build_object('amount_minor', 0));

-- Future-only free price for the upcoming tier
select fx_event_ticket_price_window(:'ticketUpcomingPriceWindowID', :'ticketUpcomingTypeID', jsonb_build_object(
    'amount_minor', 0,
    'starts_at', current_timestamp + interval '1 day'
));

-- Current free price for the active-purchase waitlist tier
select fx_event_ticket_price_window(:'ticketWaitlistActivePurchasePriceWindowID', :'ticketWaitlistActivePurchaseTypeID', jsonb_build_object('amount_minor', 0));

-- Dedicated queue row for duplicate-join FIFO coverage
insert into event_waitlist (
    created_at,
    event_id,
    event_ticket_type_id,
    user_id
) values (
    '2001-01-01 00:00:00+00',
    :'eventTicketedID',
    :'ticketTypeID',
    :'duplicateWaitlistUserID'
);

-- Completed free purchases that own the confirmed attendees' seats
insert into event_purchase (
    amount_minor,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values
    (0, 0, :'eventFullNoWaitlistID', :'ticketFullNoWaitlistHolderPurchaseID', :'ticketFullNoWaitlistTypeID', 'completed', 'General Admission', :'user1ID'),
    (0, 0, :'eventFullWaitlistID', :'ticketFullWaitlistHolderPurchaseID', :'ticketFullWaitlistTypeID', 'completed', 'General Admission', :'user1ID'),
    (0, 0, :'eventQuestionsFullWaitlistID', :'ticketQuestionsSeatPurchaseID', :'ticketQuestionsFullWaitlistTypeID', 'completed', 'General Admission', :'questionsSeatUserID');

-- Pending free checkout that must not be confirmable through the RSVP endpoint
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
    null,
    :'eventTicketedID',
    :'ticketPendingPurchaseID',
    :'ticketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'Free admission',
    :'user10ID'
);

-- Completed purchase occupying the second public ticket tier
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    null,
    :'eventTicketedID',
    :'ticketSecondHolderPurchaseID',
    :'ticketSecondTypeID',
    'completed',
    'Second admission',
    :'user7ID'
);

-- Completed purchase occupying the no-waitlist failure tier
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    null,
    :'eventTicketSoldOutNoWaitlistID',
    :'ticketSoldOutNoWaitlistHolderPurchaseID',
    :'ticketSoldOutNoWaitlistTypeID',
    'completed',
    'Sold out admission',
    :'ticketSoldOutNoWaitlistHolderUserID'
);

-- Pending checkout occupying the active-purchase waitlist failure tier
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
    null,
    :'eventTicketWaitlistActivePurchaseID',
    :'ticketWaitlistActivePurchaseID',
    :'ticketWaitlistActivePurchaseTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'Active purchase admission',
    :'ticketWaitlistActivePurchaseUserID'
);

-- Expired free checkout retried through the simple RSVP path
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
    null,
    :'eventTicketAvailableID',
    :'ticketExpiredPurchaseID',
    :'ticketAvailableTypeID',
    current_timestamp - interval '10 minutes',
    'pending',
    'Available admission',
    :'ticketExpiredPurchaseUserID'
);

-- Active ticket purchase that blocks a duplicate approval request
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
    null,
    :'eventTicketApprovalID',
    :'activeApprovalPurchaseID',
    :'ticketApprovalTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'Public approval admission',
    :'activeApprovalPurchaseUserID'
);

-- Live free checkout hold on the sole public tier of the simple RSVP event
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
    null,
    :'eventSimpleRsvpHoldID',
    :'ticketSimpleRsvpHoldPurchaseID',
    :'ticketSimpleRsvpHoldTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'Simple RSVP admission',
    :'ticketSimpleRsvpHoldUserID'
);

-- Live free checkout hold on the invitation-only tier of the simple RSVP event
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
    null,
    :'eventSimpleRsvpBlockedHoldID',
    :'ticketSimpleRsvpBlockedHoldPurchaseID',
    :'ticketSimpleRsvpBlockedHoldPrivateTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'Invitation-only admission',
    :'ticketSimpleRsvpBlockedHoldUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should prepare checkout for a user with canceled attendance history
select is(
    attend_event(:'communityID'::uuid, :'eventCanceledHistoryID'::uuid, :'user10ID'::uuid),
    'pending-payment',
    'Should prepare checkout for a user with canceled attendance history'
);

-- Should preserve canceled attendance metadata before checkout
select results_eq(
    format($$
        select
            attendance_canceled_at,
            attendance_canceled_by_user_id,
            status
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventCanceledHistoryID', :'user10ID'),
    format(
        $$ values (
            '2001-01-01 00:00:00+00'::timestamptz,
            %L::uuid,
            'attendance-canceled'::text
        ) $$,
        :'user7ID'
    ),
    'Should preserve canceled attendance metadata before checkout'
);

-- Should send direct enrollment through checkout when capacity allows
select is(
    attend_event(:'communityID'::uuid, :'eventOKID'::uuid, :'user1ID'::uuid),
    'pending-payment',
    'Should send direct enrollment through checkout when capacity allows'
);

-- Should ignore answers on the checkout route
-- The payload would fail validation: unknown question, missing required answer
select is(
    attend_event(
        :'questionsCommunityID'::uuid,
        :'eventQuestionsID'::uuid,
        :'questionsAttendeeUserID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "Unknown question"}]}',
            :'ignoredQuestionID'
        )::jsonb
    ),
    'pending-payment',
    'Should ignore answers on the checkout route'
);

-- Should not create attendance before checkout completes
select ok(
    not exists(
        select 1
        from event_attendee
        where (event_id, user_id) in (
            (:'eventOKID'::uuid, :'user1ID'::uuid),
            (:'eventQuestionsID'::uuid, :'questionsAttendeeUserID'::uuid)
        )
    ),
    'Should not create attendance before checkout completes'
);

-- Should require a tier when the event cannot auto-select one
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventTicketedID', :'user2ID'
    ),
    'OCG01',
    'ticket type is required',
    'Should require a tier when the event cannot auto-select one'
);

-- Should require a tier when no public tier is selectable
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventTicketUnavailableID', :'user1ID'
    ),
    'OCG01',
    'ticket type is required',
    'Should require a tier when no public tier is selectable'
);

-- Should reject selection of a public tier without a current price
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID', :'eventTicketUnavailableID', :'user1ID', :'ticketUpcomingTypeID'
    ),
    'OCG01',
    'ticket type is required',
    'Should reject selection of a public tier without a current price'
);

-- Should reject approval requests with an active admission offer
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID',
        :'eventTicketApprovalID',
        :'activeApprovalOfferUserID',
        :'ticketApprovalTypeID'
    ),
    'OCG01',
    'user already has an active admission offer for this event',
    'Should reject approval requests with an active admission offer'
);

-- Should reject approval requests with an active purchase
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID',
        :'eventTicketApprovalID',
        :'activeApprovalPurchaseUserID',
        :'ticketApprovalTypeID'
    ),
    'OCG01',
    'user already has an active purchase for this event',
    'Should reject approval requests with an active purchase'
);

-- Should auto-select the sole public tier for an approval request
select is(
    attend_event(:'communityID'::uuid, :'eventTicketApprovalID'::uuid, :'user3ID'::uuid),
    'pending-approval',
    'Should auto-select the sole public tier for an approval request'
);

-- Should retain the requested public ticket tier
select is(
    (
        select event_ticket_type_id
        from event_invitation_request
        where event_id = :'eventTicketApprovalID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    :'ticketApprovalTypeID'::uuid,
    'Should retain the requested public ticket tier'
);

-- Should create a generic request for a fully private event
select is(
    attend_event(
        :'communityID'::uuid,
        :'eventTicketPrivateSelectionID'::uuid,
        :'ticketPrivateSelectionUserID'::uuid
    ),
    'pending-approval',
    'Should create a generic request for a fully private event'
);

-- Should keep a generic private request unscoped until organizer review
select ok(
    exists (
        select 1
        from event_invitation_request
        where event_id = :'eventTicketPrivateSelectionID'::uuid
        and event_ticket_type_id is null
        and user_id = :'ticketPrivateSelectionUserID'::uuid
    ),
    'Should keep a generic private request unscoped until organizer review'
);

-- Should reject attendee selection of an invitation-only tier
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID',
        :'eventTicketPrivateSelectionID',
        :'ticketPrivateSelectionUserID',
        :'ticketPrivateSelectionTypeID'
    ),
    'OCG01',
    'ticket type is required',
    'Should reject attendee selection of an invitation-only tier'
);

-- Should reject another event's tier when the approval event has no public tier
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID',
        :'eventTicketPrivateApprovalID',
        :'user1ID',
        :'ticketApprovalTypeID'
    ),
    'OCG01',
    'ticket type is required',
    'Should reject another event''s tier when the approval event has no public tier'
);

-- Should prepare checkout while the selected tier has seats
select is(
    attend_event(
        :'communityID',
        :'eventTicketAvailableID',
        :'ticketAvailableUserID',
        null,
        :'ticketAvailableTypeID'
    ),
    'pending-payment',
    'Should prepare checkout while the selected tier has seats'
);

-- Should report unavailable capacity when a sold-out tier has no waitlist
select is(
    attend_event(
        :'communityID',
        :'eventTicketSoldOutNoWaitlistID',
        :'ticketSoldOutNoWaitlistUserID',
        null,
        :'ticketSoldOutNoWaitlistTypeID'
    ),
    'event-capacity-unavailable',
    'Should report unavailable capacity when a sold-out tier has no waitlist'
);

-- Should resume an active free checkout instead of joining the waitlist
select is(
    attend_event(
        :'communityID',
        :'eventTicketWaitlistActivePurchaseID',
        :'ticketWaitlistActivePurchaseUserID',
        null,
        :'ticketWaitlistActivePurchaseTypeID'
    ),
    'pending-payment',
    'Should resume an active free checkout instead of joining the waitlist'
);

-- Should resume a free checkout hold on the sole public tier without a selected tier
select is(
    attend_event(
        :'communityID'::uuid,
        :'eventSimpleRsvpHoldID'::uuid,
        :'ticketSimpleRsvpHoldUserID'::uuid
    ),
    'pending-payment',
    'Should resume a free checkout hold on the sole public tier without a selected tier'
);

-- Should keep the resumed free checkout hold as the only purchase
select results_eq(
    format($$
        select event_purchase_id, status
        from event_purchase
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventSimpleRsvpHoldID', :'ticketSimpleRsvpHoldUserID'),
    format($$ values (%L::uuid, 'pending'::text) $$, :'ticketSimpleRsvpHoldPurchaseID'),
    'Should keep the resumed free checkout hold as the only purchase'
);

-- Should reject a simple RSVP when the live hold is on another tier
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventSimpleRsvpBlockedHoldID', :'ticketSimpleRsvpBlockedHoldUserID'
    ),
    'OCG01',
    'user already has an active purchase for this event',
    'Should reject a simple RSVP when the live hold is on another tier'
);

-- Should retry after expiring a stale free checkout hold
select is(
    attend_event(
        :'communityID',
        :'eventTicketAvailableID',
        :'ticketExpiredPurchaseUserID',
        null,
        :'ticketAvailableTypeID'
    ),
    'pending-payment',
    'Should retry after expiring a stale free checkout hold'
);

-- Should mark the stale free checkout hold expired before retrying
select is(
    (
        select status
        from event_purchase
        where event_purchase_id = :'ticketExpiredPurchaseID'
    ),
    'expired',
    'Should mark the stale free checkout hold expired before retrying'
);

-- Should join a sold-out public ticket tier waitlist
select is(
    attend_event(
        :'communityID'::uuid,
        :'eventTicketedID'::uuid,
        :'user2ID'::uuid,
        null,
        :'ticketTypeID'::uuid
    ),
    'waitlisted',
    'Should join a sold-out public ticket tier waitlist'
);

-- Should retain the selected ticket tier on the waitlist entry
select is(
    (
        select event_ticket_type_id
        from event_waitlist
        where event_id = :'eventTicketedID'::uuid
        and user_id = :'user2ID'::uuid
    ),
    :'ticketTypeID'::uuid,
    'Should retain the selected ticket tier on the waitlist entry'
);

-- Should keep duplicate joins to the same tier idempotent
select is(
    attend_event(
        :'communityID',
        :'eventTicketedID',
        :'duplicateWaitlistUserID',
        null,
        :'ticketTypeID'
    ),
    'waitlisted',
    'Should keep duplicate joins to the same tier idempotent'
);

-- Should retain the waitlist FIFO timestamp after a duplicate join
select is(
    (
        select created_at
        from event_waitlist
        where event_id = :'eventTicketedID'::uuid
        and user_id = :'duplicateWaitlistUserID'::uuid
    ),
    '2001-01-01 00:00:00+00'::timestamptz,
    'Should retain the waitlist FIFO timestamp after a duplicate join'
);

-- Should move an existing waitlist user to another sold-out tier
select is(
    attend_event(
        :'communityID'::uuid,
        :'eventTicketedID'::uuid,
        :'user2ID'::uuid,
        null,
        :'ticketSecondTypeID'::uuid
    ),
    'waitlisted',
    'Should move an existing waitlist user to another sold-out tier'
);

-- Should keep a single waitlist entry on the new tier after a move
select results_eq(
    format($$
        select event_ticket_type_id
        from event_waitlist
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventTicketedID', :'user2ID'),
    format($$ values (%L::uuid) $$, :'ticketSecondTypeID'),
    'Should keep a single waitlist entry on the new tier after a move'
);

-- Should reject confirming an unpaid ticket checkout through direct RSVP
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventTicketedID', :'user10ID'
    ),
    'OCG01',
    'user already has an active purchase for this event',
    'Should reject confirming an unpaid ticket checkout through direct RSVP'
);

-- Should reject attendee registration after the registration window closes
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventRegistrationClosedID', :'user7ID'
    ),
    'OCG01',
    'event registration is not open',
    'Should reject attendee registration after the registration window closes'
);

-- Should apply capacity checks when a canceled attendee rejoins
select is(
    attend_event(
        :'communityID'::uuid,
        :'eventFullNoWaitlistID'::uuid,
        :'user7ID'::uuid
    ),
    'event-capacity-unavailable',
    'Should apply capacity checks when a canceled attendee rejoins'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventFullNoWaitlistID'::uuid
        and user_id = :'user7ID'::uuid
    ),
    'attendance-canceled',
    'Should preserve canceled attendance after a sold-out rejoin is rejected'
);

-- Should reject duplicate RSVP for a confirmed attendee
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventFullNoWaitlistID', :'user1ID'
    ),
    'OCG01',
    'user is already attending this event',
    'Should reject duplicate RSVP for a confirmed attendee'
);

-- Should apply capacity checks after a rejected organizer invitation
select is(
    attend_event(:'communityID'::uuid, :'eventFullNoWaitlistID'::uuid, :'user6ID'::uuid),
    'event-capacity-unavailable',
    'Should apply capacity checks after a rejected organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventFullNoWaitlistID'::uuid
        and user_id = :'user6ID'::uuid
    ),
    'invitation-rejected',
    'Should preserve rejected organizer invitation history'
);

-- Should allow RSVP after an organizer invitation was canceled
select is(
    attend_event(:'communityID'::uuid, :'eventOKID'::uuid, :'user3ID'::uuid),
    'pending-payment',
    'Should allow RSVP after an organizer invitation was canceled'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventOKID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'invitation-canceled',
    'Should preserve canceled organizer invitation history before checkout'
);

select ok(
    (
        select manually_invited
        from event_attendee
        where event_id = :'eventOKID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Should preserve manually invited metadata before checkout'
);

-- Should place the user on the waitlist when the event is full and waitlist is enabled
select is(
    attend_event(:'communityID'::uuid, :'eventFullWaitlistID'::uuid, :'user2ID'::uuid),
    'waitlisted',
    'Should place the user on the waitlist when the event is full and waitlist is enabled'
);

-- Should create a waitlist row after joining the waitlist
select ok(
    exists(
        select 1
        from event_waitlist
        where event_id = :'eventFullWaitlistID'::uuid and user_id = :'user2ID'::uuid
    ),
    'Should create a waitlist row after joining the waitlist'
);

-- Should allow waitlist join after an organizer invitation was canceled
select is(
    attend_event(:'communityID'::uuid, :'eventFullWaitlistID'::uuid, :'user3ID'::uuid),
    'waitlisted',
    'Should allow waitlist join after an organizer invitation was canceled'
);

select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventFullWaitlistID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Should remove the canceled organizer invitation row before waitlisting'
);

select ok(
    exists(
        select 1
        from event_waitlist
        where event_id = :'eventFullWaitlistID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Should create a waitlist row after a canceled organizer invitation'
);

-- Should move a canceled attendee to the waitlist when the event is full
select is(
    attend_event(:'communityID'::uuid, :'eventFullWaitlistID'::uuid, :'user4ID'::uuid),
    'waitlisted',
    'Should move a canceled attendee to the waitlist when the event is full'
);

select results_eq(
    format($$
        select
            exists(
                select 1
                from event_attendee
                where event_id = %L::uuid
                and user_id = %L::uuid
            ),
            exists(
                select 1
                from event_waitlist
                where event_id = %L::uuid
                and user_id = %L::uuid
            )
    $$, :'eventFullWaitlistID', :'user4ID', :'eventFullWaitlistID', :'user4ID'),
    $$ values (false, true) $$,
    'Should move canceled attendance into the waitlist without a cross-table duplicate'
);

-- Should allow waitlist joins without registration answers when questions exist
select is(
    attend_event(
        :'questionsCommunityID'::uuid,
        :'eventQuestionsFullWaitlistID'::uuid,
        :'questionsWaitlistUserID'::uuid
    ),
    'waitlisted',
    'Should allow waitlist joins without registration answers when questions exist'
);

-- Should create only a waitlist row when joining a question-enabled waitlist without answers
select is(
    (
        select jsonb_build_object(
            'attendee_exists', exists(
                select 1
                from event_attendee
                where event_id = :'eventQuestionsFullWaitlistID'::uuid
                and user_id = :'questionsWaitlistUserID'::uuid
            ),
            'waitlist_exists', exists(
                select 1
                from event_waitlist
                where event_id = :'eventQuestionsFullWaitlistID'::uuid
                and user_id = :'questionsWaitlistUserID'::uuid
            )
        )
    ),
    '{"attendee_exists":false,"waitlist_exists":true}'::jsonb,
    'Should create only a waitlist row when joining a question-enabled waitlist without answers'
);

-- Should require accepted requests to continue through their admission offer
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInviteOnlyID', :'user3ID'
    ),
    'OCG01',
    'invitation request was already accepted for this event',
    'Should require accepted requests to continue through their admission offer'
);

-- Should create a pending invitation request when approval is required
select is(
    attend_event(:'communityID'::uuid, :'eventInviteOnlyID'::uuid, :'user2ID'::uuid),
    'pending-approval',
    'Should create a pending invitation request when approval is required'
);

-- Should not create an attendee row before approval
select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventInviteOnlyID'::uuid and user_id = :'user2ID'::uuid
    ),
    'Should not create an attendee row before approval'
);

-- Should create a pending invitation request row
select ok(
    exists(
        select 1
        from event_invitation_request
        where event_id = :'eventInviteOnlyID'::uuid
        and user_id = :'user2ID'::uuid
        and status = 'pending'
    ),
    'Should create a pending invitation request row'
);

-- Should reject duplicate invitation requests
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInviteOnlyID', :'user2ID'
    ),
    'OCG01',
    'user has already requested an invitation for this event',
    'Should reject duplicate invitation requests'
);

-- Should reject users whose invitation request was rejected
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInviteOnlyID', :'user4ID'
    ),
    'OCG01',
    'invitation request was rejected for this event',
    'Should reject users whose invitation request was rejected'
);

-- Should reject unpublished events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventUnpublishedID', :'user1ID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject unpublished events'
);

-- Should keep approval-required attendance pending and store answers on the request
select is(
    attend_event(
        :'questionsCommunityID'::uuid,
        :'eventQuestionsApprovalID'::uuid,
        :'questionsRequestUserID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "Request answer"}]}',
            :'questionID'
        )::jsonb
    ),
    'pending-approval',
    'Should keep approval-required attendance pending and store answers on the request'
);

-- Should store answers on pending invitation requests
select is(
    (
        select registration_answers
        from event_invitation_request
        where event_id = :'eventQuestionsApprovalID'::uuid
        and user_id = :'questionsRequestUserID'::uuid
    ),
    format(
        '{"answers": [{"question_id": "%s", "value": "Request answer"}]}',
        :'questionID'
    )::jsonb,
    'Should store answers on pending invitation requests'
);

-- Should require registration answers for approval requests
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'questionsCommunityID', :'eventQuestionsApprovalID', :'questionsMissingAnswersUserID'
    ),
    'OCG01',
    'questionnaire answers are required',
    'Should require registration answers for approval requests'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
