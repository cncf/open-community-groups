-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(77);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5e020000-0000-0000-0000-000000000001'
\set eventCanceledID '5e020000-0000-0000-0000-000000000002'
\set eventCategoryID '5e020000-0000-0000-0000-000000000003'
\set eventDeletedID '5e020000-0000-0000-0000-000000000004'
\set eventFullNoWaitlistID '5e020000-0000-0000-0000-000000000005'
\set eventFullWaitlistID '5e020000-0000-0000-0000-000000000006'
\set eventInactiveGroupID '5e020000-0000-0000-0000-000000000007'
\set eventInviteOnlyID '5e020000-0000-0000-0000-000000000008'
\set eventOKID '5e020000-0000-0000-0000-000000000009'
\set eventPastID '5e020000-0000-0000-0000-00000000000a'
\set eventQuestionsApprovalID '5e020000-0000-0000-0000-00000000000b'
\set eventQuestionsFullWaitlistID '5e020000-0000-0000-0000-00000000000c'
\set eventQuestionsID '5e020000-0000-0000-0000-00000000000d'
\set eventReactivationID '5e020000-0000-0000-0000-00000000002b'
\set eventRegistrationClosedID '5e020000-0000-0000-0000-000000000025'
\set eventRegistrationOpenUntilStartID '5e020000-0000-0000-0000-000000000029'
\set eventRegistrationUpcomingID '5e020000-0000-0000-0000-000000000026'
\set eventUnpublishedID '5e020000-0000-0000-0000-00000000000e'
\set eventTicketedID '5e020000-0000-0000-0000-00000000002d'
\set eventTicketApprovalID '5e020000-0000-0000-0000-000000000036'
\set eventTicketAvailableID '5e020000-0000-0000-0000-000000000040'
\set eventTicketPrivateApprovalID '5e020000-0000-0000-0000-000000000037'
\set eventTicketPrivateSelectionID '5e020000-0000-0000-0000-000000000041'
\set eventTicketSoldOutNoWaitlistID '5e020000-0000-0000-0000-000000000042'
\set eventTicketWaitlistActivePurchaseID '5e020000-0000-0000-0000-000000000043'
\set activeApprovalOfferID '5e020000-0000-0000-0000-00000000003c'
\set activeApprovalOfferUserID '5e020000-0000-0000-0000-00000000003d'
\set activeApprovalPurchaseID '5e020000-0000-0000-0000-00000000003e'
\set activeApprovalPurchaseUserID '5e020000-0000-0000-0000-00000000003f'
\set groupCategoryID '5e020000-0000-0000-0000-00000000000f'
\set groupID '5e020000-0000-0000-0000-000000000010'
\set ignoredQuestionID '5e020000-0000-0000-0000-000000000011'
\set inactiveGroupID '5e020000-0000-0000-0000-000000000012'
\set questionID '5e020000-0000-0000-0000-000000000013'
\set questionsAttendeeUserID '5e020000-0000-0000-0000-000000000014'
\set questionsCommunityID '5e020000-0000-0000-0000-000000000015'
\set questionsEventCategoryID '5e020000-0000-0000-0000-000000000016'
\set questionsGroupCategoryID '5e020000-0000-0000-0000-000000000017'
\set questionsGroupID '5e020000-0000-0000-0000-000000000018'
\set questionsPendingUserID '5e020000-0000-0000-0000-000000000019'
\set questionsRejoinConflictUserID '5e020000-0000-0000-0000-00000000001a'
\set questionsRejoinInsertUserID '5e020000-0000-0000-0000-00000000001b'
\set questionsRequestUserID '5e020000-0000-0000-0000-00000000001c'
\set questionsSeatUserID '5e020000-0000-0000-0000-00000000001d'
\set questionsWaitlistUserID '5e020000-0000-0000-0000-00000000001e'
\set user1ID '5e020000-0000-0000-0000-00000000001f'
\set user2ID '5e020000-0000-0000-0000-000000000020'
\set user3ID '5e020000-0000-0000-0000-000000000021'
\set user4ID '5e020000-0000-0000-0000-000000000022'
\set user5ID '5e020000-0000-0000-0000-000000000023'
\set user6ID '5e020000-0000-0000-0000-000000000024'
\set user7ID '5e020000-0000-0000-0000-000000000027'
\set user8ID '5e020000-0000-0000-0000-000000000028'
\set user9ID '5e020000-0000-0000-0000-00000000002a'
\set user10ID '5e020000-0000-0000-0000-00000000002c'
\set ticketAvailablePriceWindowID '5e020000-0000-0000-0000-000000000044'
\set ticketAvailableTypeID '5e020000-0000-0000-0000-000000000045'
\set ticketAvailableUserID '5e020000-0000-0000-0000-000000000046'
\set ticketPriceWindowID '5e020000-0000-0000-0000-00000000002f'
\set ticketPendingPurchaseID '5e020000-0000-0000-0000-000000000030'
\set ticketPrivateSelectionPriceWindowID '5e020000-0000-0000-0000-000000000047'
\set ticketPrivateSelectionTypeID '5e020000-0000-0000-0000-000000000048'
\set ticketPrivateSelectionUserID '5e020000-0000-0000-0000-000000000049'
\set ticketPrivatePriceWindowID '5e020000-0000-0000-0000-000000000031'
\set ticketPrivateTypeID '5e020000-0000-0000-0000-000000000032'
\set ticketSecondHolderPurchaseID '5e020000-0000-0000-0000-000000000033'
\set ticketSecondPriceWindowID '5e020000-0000-0000-0000-000000000034'
\set ticketSecondTypeID '5e020000-0000-0000-0000-000000000035'
\set ticketSoldOutNoWaitlistHolderPurchaseID '5e020000-0000-0000-0000-00000000004a'
\set ticketSoldOutNoWaitlistHolderUserID '5e020000-0000-0000-0000-00000000004b'
\set ticketSoldOutNoWaitlistPriceWindowID '5e020000-0000-0000-0000-00000000004c'
\set ticketSoldOutNoWaitlistTypeID '5e020000-0000-0000-0000-00000000004d'
\set ticketSoldOutNoWaitlistUserID '5e020000-0000-0000-0000-00000000004e'
\set ticketTypeID '5e020000-0000-0000-0000-00000000002e'
\set ticketApprovalPriceWindowID '5e020000-0000-0000-0000-000000000038'
\set ticketApprovalTypeID '5e020000-0000-0000-0000-000000000039'
\set ticketPrivateApprovalPriceWindowID '5e020000-0000-0000-0000-00000000003a'
\set ticketPrivateApprovalTypeID '5e020000-0000-0000-0000-00000000003b'
\set ticketWaitlistActivePurchaseID '5e020000-0000-0000-0000-00000000004f'
\set ticketWaitlistActivePurchasePriceWindowID '5e020000-0000-0000-0000-000000000050'
\set ticketWaitlistActivePurchaseTypeID '5e020000-0000-0000-0000-000000000051'
\set ticketWaitlistActivePurchaseUserID '5e020000-0000-0000-0000-000000000052'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'questionsCommunityID',
    'attend-questions-community',
    'Attend Questions Community',
    'Community for registration-question attendance tests',
    'https://example.com/questions-banner-mobile.png',
    'https://example.com/questions-banner.png',
    'https://example.com/questions-logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategoryID', :'communityID', 'Technology'),
    (:'questionsGroupCategoryID', :'questionsCommunityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values
    (:'eventCategoryID', :'communityID', 'General'),
    (:'questionsEventCategoryID', :'questionsCommunityID', 'General');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name,
    registration_status
) values (
    :'user1ID',
    'user-1-hash',
    'user-1@example.com',
    true,
    'user-1',
    'User One',
    'registered'
), (
    :'user2ID',
    'user-2-hash',
    'user-2@example.com',
    true,
    'user-2',
    'User Two',
    'registered'
), (
    :'user3ID',
    'user-3-hash',
    'user-3@example.com',
    true,
    'user-3',
    'User Three',
    'registered'
), (
    :'user4ID',
    'user-4-hash',
    'user-4@example.com',
    true,
    'user-4',
    'User Four',
    'registered'
), (
    :'user5ID',
    'user-5-hash',
    'user-5@example.com',
    true,
    'user-5',
    'User Five',
    'registered'
), (
    :'user6ID',
    'user-6-hash',
    'user-6@example.com',
    true,
    'user-6',
    'User Six',
    'registered'
), (
    :'user7ID',
    'user-7-hash',
    'user-7@example.com',
    true,
    'user-7',
    'User Seven',
    'registered'
), (
    :'user8ID',
    'user-8-hash',
    'user-8@example.com',
    true,
    'user-8',
    'User Eight',
    'registered'
), (
    :'user9ID',
    'user-9-hash',
    'user-9@example.com',
    true,
    'user-9',
    'User Nine',
    'registered'
), (
    :'user10ID',
    'user-10-hash',
    'user-10@example.com',
    true,
    'user-10',
    'User Ten',
    'registered'
), (
    :'activeApprovalOfferUserID',
    'active-approval-offer-hash',
    'active-approval-offer@example.com',
    true,
    'active-approval-offer',
    'Active Approval Offer',
    'registered'
), (
    :'activeApprovalPurchaseUserID',
    'active-approval-purchase-hash',
    'active-approval-purchase@example.com',
    true,
    'active-approval-purchase',
    'Active Approval Purchase',
    'registered'
), (
    :'ticketAvailableUserID',
    'ticket-available-hash',
    'ticket-available@example.com',
    true,
    'ticket-available',
    'Ticket Available',
    'registered'
), (
    :'ticketPrivateSelectionUserID',
    'ticket-private-selection-hash',
    'ticket-private-selection@example.com',
    true,
    'ticket-private-selection',
    'Ticket Private Selection',
    'registered'
), (
    :'ticketSoldOutNoWaitlistHolderUserID',
    'ticket-sold-out-holder-hash',
    'ticket-sold-out-holder@example.com',
    true,
    'ticket-sold-out-holder',
    'Ticket Sold Out Holder',
    'registered'
), (
    :'ticketSoldOutNoWaitlistUserID',
    'ticket-sold-out-user-hash',
    'ticket-sold-out-user@example.com',
    true,
    'ticket-sold-out-user',
    'Ticket Sold Out User',
    'registered'
), (
    :'ticketWaitlistActivePurchaseUserID',
    'ticket-waitlist-active-purchase-hash',
    'ticket-waitlist-active-purchase@example.com',
    true,
    'ticket-waitlist-active-purchase',
    'Ticket Waitlist Active Purchase',
    'registered'
), (
    :'questionsAttendeeUserID',
    'rq-hash-1',
    'rq-attend@example.com',
    true,
    'rq-attendee',
    'Attendee',
    'registered'
), (
    :'questionsWaitlistUserID',
    'rq-hash-2',
    'rq-waitlist@example.com',
    true,
    'rq-waitlist',
    'Waitlist User',
    'registered'
), (
    :'questionsSeatUserID',
    'rq-hash-3',
    'rq-seat@example.com',
    true,
    'rq-seat',
    'Seat Holder',
    'registered'
), (
    :'questionsRequestUserID',
    'rq-hash-4',
    'rq-request@example.com',
    true,
    'rq-requester',
    'Requester',
    'registered'
), (
    :'questionsRejoinInsertUserID',
    'rq-hash-5',
    'rq-rejoin-insert@example.com',
    true,
    'rq-rejoin-insert',
    'Rejoin Insert',
    'registered'
), (
    :'questionsRejoinConflictUserID',
    'rq-hash-6',
    'rq-rejoin-conflict@example.com',
    true,
    'rq-rejoin-conflict',
    'Rejoin Conflict',
    'registered'
), (
    :'questionsPendingUserID',
    'rq-hash-7',
    'rq-pending@example.com',
    true,
    'rq-pending',
    'Pending Answers',
    'registered'
);

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Active Group',
    'active-group',
    true,
    false
), (
    :'inactiveGroupID',
    :'communityID',
    :'groupCategoryID',
    'Inactive Group',
    'inactive-group',
    false,
    false
), (
    :'questionsGroupID',
    :'questionsCommunityID',
    :'questionsGroupCategoryID',
    'Attend Questions Group',
    'attend-questions-group',
    true,
    false
);

-- Events
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    attendee_approval_required,
    canceled,
    capacity,
    deleted,
    description,
    ends_at,
    published,
    registration_ends_at,
    registration_starts_at,
    starts_at,
    timezone,
    waitlist_enabled
)
values
    (
        :'eventOKID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'OK',
        'ok',
        false,
        false,
        null,
        false,
        'Test event',
        null,
        true,
        null,
        null,
        null,
        'UTC',
        false
    ),
    (
        :'eventUnpublishedID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Unpublished',
        'unpublished',
        false,
        false,
        null,
        false,
        'Test event',
        null,
        false,
        null,
        null,
        null,
        'UTC',
        false
    ),
    (
        :'eventCanceledID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Canceled',
        'canceled',
        false,
        true,
        null,
        false,
        'Test event',
        null,
        false,
        null,
        null,
        null,
        'UTC',
        false
    ),
    (
        :'eventDeletedID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Deleted',
        'deleted',
        false,
        false,
        null,
        true,
        'Test event',
        null,
        false,
        null,
        null,
        null,
        'UTC',
        false
    ),
    (
        :'eventInactiveGroupID',
        :'eventCategoryID',
        'in-person',
        :'inactiveGroupID',
        'Inactive Group',
        'inactive-group',
        false,
        false,
        null,
        false,
        'Test event',
        null,
        true,
        null,
        null,
        null,
        'UTC',
        false
    ),
    (
        :'eventPastID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Past',
        'past',
        false,
        false,
        null,
        false,
        'Past event',
        current_timestamp - interval '1 hour',
        true,
        null,
        null,
        current_timestamp - interval '2 hours',
        'UTC',
        false
    ),
    (
        :'eventFullNoWaitlistID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Full No Waitlist',
        'full-no-waitlist',
        false,
        false,
        2,
        false,
        'Full event',
        null,
        true,
        null,
        null,
        null,
        'UTC',
        false
    ),
    (
        :'eventFullWaitlistID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Full Waitlist',
        'full-waitlist',
        false,
        false,
        1,
        false,
        'Waitlist event',
        null,
        true,
        null,
        null,
        null,
        'UTC',
        true
    ),
    (
        :'eventInviteOnlyID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Invite Only',
        'invite-only',
        true,
        false,
        1,
        false,
        'Invite-only event',
        null,
        true,
        null,
        null,
        null,
        'UTC',
        false
    ),
    (
        :'eventRegistrationClosedID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Registration Closed',
        'registration-closed',
        false,
        false,
        null,
        false,
        'Closed registration event',
        null,
        true,
        current_timestamp - interval '1 hour',
        null,
        '2030-01-04 10:00:00+00',
        'UTC',
        false
    ),
    (
        :'eventRegistrationUpcomingID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Registration Upcoming',
        'registration-upcoming',
        false,
        false,
        null,
        false,
        'Upcoming registration event',
        null,
        true,
        current_timestamp + interval '2 days',
        current_timestamp + interval '1 day',
        '2030-01-05 10:00:00+00',
        'UTC',
        false
    ),
    (
        :'eventRegistrationOpenUntilStartID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Registration Open Until Start',
        'registration-open-until-start',
        false,
        false,
        null,
        false,
        'Open-only registration event',
        current_timestamp + interval '1 hour',
        true,
        null,
        current_timestamp - interval '2 hours',
        current_timestamp - interval '1 hour',
        'UTC',
        false
    ),
    (
        :'eventReactivationID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Reactivation',
        'reactivation',
        false,
        false,
        null,
        false,
        'Canceled attendance reactivation event',
        null,
        true,
        null,
        null,
        null,
        'UTC',
        false
    );

-- Ticketed event used to reject direct RSVP enrollment
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
    timezone,
    waitlist_enabled
) values
    (
        false,
        'Ticketed event',
        :'eventCategoryID',
        :'eventTicketedID',
        'in-person',
        :'groupID',
        'Ticketed',
        true,
        'ticketed',
        'UTC',
        true
    ),
    (
        true,
        'Public ticket approval event',
        :'eventCategoryID',
        :'eventTicketApprovalID',
        'in-person',
        :'groupID',
        'Public Ticket Approval',
        true,
        'public-ticket-approval',
        'UTC',
        false
    ),
    (
        true,
        'Private ticket approval event',
        :'eventCategoryID',
        :'eventTicketPrivateApprovalID',
        'in-person',
        :'groupID',
        'Private Ticket Approval',
        true,
        'private-ticket-approval',
        'UTC',
        false
    );

-- Ticketed events used by private-request and waitlist failure branches
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
    timezone,
    waitlist_enabled
) values
    (
        false,
        'Ticketed event with remaining public seats',
        :'eventCategoryID',
        :'eventTicketAvailableID',
        'in-person',
        :'groupID',
        'Ticket Still Available',
        true,
        'ticket-still-available',
        'UTC',
        true
    ),
    (
        true,
        'Private ticket approval event with no public tiers',
        :'eventCategoryID',
        :'eventTicketPrivateSelectionID',
        'in-person',
        :'groupID',
        'Private Ticket Selection',
        true,
        'private-ticket-selection',
        'UTC',
        false
    ),
    (
        false,
        'Sold-out ticketed event without a waitlist',
        :'eventCategoryID',
        :'eventTicketSoldOutNoWaitlistID',
        'in-person',
        :'groupID',
        'Sold Out No Waitlist',
        true,
        'sold-out-no-waitlist',
        'UTC',
        false
    ),
    (
        false,
        'Sold-out ticketed event with an active requester purchase',
        :'eventCategoryID',
        :'eventTicketWaitlistActivePurchaseID',
        'in-person',
        :'groupID',
        'Waitlist Active Purchase',
        true,
        'waitlist-active-purchase',
        'UTC',
        true
    );

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
        :'eventTicketedID',
        :'ticketTypeID',
        1,
        1,
        'Free admission'
    ),
    (
        true,
        'public',
        :'eventTicketedID',
        :'ticketSecondTypeID',
        2,
        1,
        'Second admission'
    ),
    (
        true,
        'public',
        :'eventTicketApprovalID',
        :'ticketApprovalTypeID',
        1,
        10,
        'Approval admission'
    ),
    (
        true,
        'invitation_only',
        :'eventTicketPrivateApprovalID',
        :'ticketPrivateApprovalTypeID',
        1,
        10,
        'Private approval admission'
    ),
    (
        true,
        'invitation_only',
        :'eventTicketedID',
        :'ticketPrivateTypeID',
        3,
        1,
        'Private admission'
    );

-- Ticket tiers used by private-request and waitlist failure branches
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
        :'eventTicketAvailableID',
        :'ticketAvailableTypeID',
        1,
        2,
        'Available admission'
    ),
    (
        true,
        'invitation_only',
        :'eventTicketPrivateSelectionID',
        :'ticketPrivateSelectionTypeID',
        1,
        10,
        'Private selection admission'
    ),
    (
        true,
        'public',
        :'eventTicketSoldOutNoWaitlistID',
        :'ticketSoldOutNoWaitlistTypeID',
        1,
        1,
        'Sold out admission'
    ),
    (
        true,
        'public',
        :'eventTicketWaitlistActivePurchaseID',
        :'ticketWaitlistActivePurchaseTypeID',
        1,
        1,
        'Active purchase admission'
    );

insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values
    (0, :'ticketPriceWindowID', :'ticketTypeID'),
    (0, :'ticketApprovalPriceWindowID', :'ticketApprovalTypeID'),
    (0, :'ticketPrivateApprovalPriceWindowID', :'ticketPrivateApprovalTypeID'),
    (0, :'ticketSecondPriceWindowID', :'ticketSecondTypeID'),
    (0, :'ticketPrivatePriceWindowID', :'ticketPrivateTypeID');

-- Current prices used by private-request and waitlist failure branch tiers
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values
    (0, :'ticketAvailablePriceWindowID', :'ticketAvailableTypeID'),
    (0, :'ticketPrivateSelectionPriceWindowID', :'ticketPrivateSelectionTypeID'),
    (0, :'ticketSoldOutNoWaitlistPriceWindowID', :'ticketSoldOutNoWaitlistTypeID'),
    (0, :'ticketWaitlistActivePurchasePriceWindowID', :'ticketWaitlistActivePurchaseTypeID');

-- Events requiring registration answers during attendance
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    attendee_approval_required,
    capacity,
    description,
    published,
    registration_questions,
    starts_at,
    timezone,
    waitlist_enabled
) values (
    :'eventQuestionsID',
    :'questionsEventCategoryID',
    'in-person',
    :'questionsGroupID',
    'Questions Event',
    'questions-event',
    false,
    null,
    'Event requiring registration answers',
    true,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    '2030-01-01 10:00:00+00',
    'UTC',
    false
), (
    :'eventQuestionsApprovalID',
    :'questionsEventCategoryID',
    'in-person',
    :'questionsGroupID',
    'Approval Questions Event',
    'approval-questions-event',
    true,
    null,
    'Approval-required event with registration answers',
    true,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    '2030-01-02 10:00:00+00',
    'UTC',
    false
), (
    :'eventQuestionsFullWaitlistID',
    :'questionsEventCategoryID',
    'in-person',
    :'questionsGroupID',
    'Questions Full Waitlist Event',
    'questions-full-waitlist-event',
    false,
    1,
    'Full waitlist event with registration answers',
    true,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    '2030-01-03 10:00:00+00',
    'UTC',
    true
);

-- Event attendees
insert into event_attendee (event_id, user_id, status)
values
    (:'eventFullNoWaitlistID', :'user1ID', 'confirmed'),
    (:'eventFullWaitlistID', :'user1ID', 'confirmed'),
    (:'eventQuestionsFullWaitlistID', :'questionsSeatUserID', 'confirmed'),
    (:'eventQuestionsID', :'questionsPendingUserID', 'registration-questions-pending');

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

-- Canceled attendee row reactivated by a new RSVP
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values (
    current_timestamp,
    :'user10ID',
    :'eventReactivationID',
    'attendance-canceled',
    :'user10ID'
);

-- Stale canceled attendee row for accepted approval-request rejoin tests
insert into event_attendee (event_id, user_id, registration_answers, status)
values (
    :'eventQuestionsApprovalID',
    :'questionsRejoinConflictUserID',
    format(
        '{"answers": [{"question_id": "%s", "value": "Stale answer"}]}',
        :'questionID'
    )::jsonb,
    'invitation-canceled'
);

-- Existing organizer invitation decisions
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'eventOKID', :'user3ID', true, 'invitation-canceled'),
    (:'eventFullWaitlistID', :'user3ID', false, 'invitation-canceled'),
    (:'eventFullNoWaitlistID', :'user5ID', true, 'invitation-pending'),
    (:'eventFullNoWaitlistID', :'user6ID', true, 'invitation-rejected'),
    (:'eventRegistrationClosedID', :'user8ID', true, 'invitation-pending'),
    (:'eventRegistrationOpenUntilStartID', :'user9ID', true, 'invitation-pending'),
    (:'eventTicketedID', :'user9ID', true, 'invitation-pending'),
    (:'eventTicketedID', :'user10ID', false, 'registration-questions-pending');

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

-- Event invitation requests
insert into event_invitation_request (
    event_id,
    user_id,
    created_at,
    status,
    reviewed_at,
    reviewed_by
)
values
    (
        :'eventInviteOnlyID',
        :'user3ID',
        '2024-01-01 00:00:00+00',
        'accepted',
        '2024-01-01 01:00:00+00',
        :'user1ID'
    ),
    (
        :'eventInviteOnlyID',
        :'user4ID',
        '2024-01-02 00:00:00+00',
        'rejected',
        '2024-01-02 01:00:00+00',
        :'user1ID'
    ),
    (
        :'eventQuestionsApprovalID',
        :'questionsRejoinInsertUserID',
        '2024-01-03 00:00:00+00',
        'accepted',
        '2024-01-03 01:00:00+00',
        :'user1ID'
    ),
    (
        :'eventQuestionsApprovalID',
        :'questionsRejoinConflictUserID',
        '2024-01-04 00:00:00+00',
        'accepted',
        '2024-01-04 01:00:00+00',
        :'user1ID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reactivate canceled attendance through a new RSVP
select is(
    attend_event(:'communityID'::uuid, :'eventReactivationID'::uuid, :'user10ID'::uuid),
    'attendee',
    'Should reactivate canceled attendance through a new RSVP'
);

-- Should clear canceled attendance metadata after the new RSVP
select results_eq(
    format($$
        select
            attendance_canceled_at,
            attendance_canceled_by_user_id,
            status
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventReactivationID', :'user10ID'),
    $$ values (null::timestamptz, null::uuid, 'confirmed'::text) $$,
    'Should clear canceled attendance metadata after the new RSVP'
);

-- Should register a normal attendee when capacity allows
select is(
    attend_event(:'communityID'::uuid, :'eventOKID'::uuid, :'user1ID'::uuid),
    'attendee',
    'Returns attendee when the user gets a confirmed seat'
);

-- Should reject direct RSVP enrollment for ticketed events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventTicketedID', :'user2ID'
    ),
    'ticketed events must be purchased before attending',
    'Rejects direct RSVP enrollment for ticketed events'
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
    'user already has an active purchase for this event',
    'Should reject approval requests with an active purchase'
);

-- Should require a ticket type for public ticket approval requests
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventTicketApprovalID', :'user3ID'
    ),
    'ticket type is required',
    'Should require a ticket type for public ticket approval requests'
);

-- Should create a public ticket approval request
select is(
    attend_event(
        :'communityID'::uuid,
        :'eventTicketApprovalID'::uuid,
        :'user3ID'::uuid,
        null,
        :'ticketApprovalTypeID'::uuid
    ),
    'pending-approval',
    'Should create a public ticket approval request'
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

-- Should reject private ticket approval requests that select a ticket type
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID',
        :'eventTicketPrivateSelectionID',
        :'ticketPrivateSelectionUserID',
        :'ticketPrivateSelectionTypeID'
    ),
    'private ticket requests cannot select a ticket type',
    'Should reject private ticket approval requests that select a ticket type'
);

select is(
    attend_event(
        :'communityID'::uuid,
        :'eventTicketPrivateApprovalID'::uuid,
        :'user5ID'::uuid
    ),
    'pending-approval',
    'Should create a generic private ticket approval request'
);

select is(
    (
        select event_ticket_type_id
        from event_invitation_request
        where event_id = :'eventTicketPrivateApprovalID'::uuid
        and user_id = :'user5ID'::uuid
    ),
    null,
    'Should leave generic private ticket requests unassigned'
);

-- Should reject waitlist joins while the selected ticket tier still has seats
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID',
        :'eventTicketAvailableID',
        :'ticketAvailableUserID',
        :'ticketAvailableTypeID'
    ),
    'ticket type is still available',
    'Should reject waitlist joins while the selected ticket tier still has seats'
);

-- Should reject waitlist joins when sold-out ticket tiers have waitlists disabled
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID',
        :'eventTicketSoldOutNoWaitlistID',
        :'ticketSoldOutNoWaitlistUserID',
        :'ticketSoldOutNoWaitlistTypeID'
    ),
    'ticket type is sold out',
    'Should reject waitlist joins when sold-out ticket tiers have waitlists disabled'
);

-- Should reject waitlist joins with an active purchase
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID',
        :'eventTicketWaitlistActivePurchaseID',
        :'ticketWaitlistActivePurchaseUserID',
        :'ticketWaitlistActivePurchaseTypeID'
    ),
    'user already has an active purchase for this event',
    'Should reject waitlist joins with an active purchase'
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
    'Should retain the selected waitlist ticket tier'
);

-- Should reject duplicate joins to the same ticket tier
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID', :'eventTicketedID', :'user2ID', :'ticketTypeID'
    ),
    'user is already on the waiting list for this ticket type',
    'Should reject duplicate joins to the same ticket tier'
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

-- Should prevent public waitlist joins for invitation-only tiers
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid,null,%L::uuid)',
        :'communityID', :'eventTicketedID', :'user4ID', :'ticketPrivateTypeID'
    ),
    'ticket type is not publicly available',
    'Should reject invitation-only ticket waitlist joins'
);

-- Should reject confirming an unpaid ticket checkout through direct RSVP
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventTicketedID', :'user10ID'
    ),
    'ticketed events must be purchased before attending',
    'Rejects unpaid pending ticket checkout rows through direct RSVP'
);

-- Should preserve legacy organizer invitation acceptance on ticketed events
select is(
    attend_event(:'communityID'::uuid, :'eventTicketedID'::uuid, :'user9ID'::uuid),
    'attendee',
    'Allows legacy organizer invitations to be accepted on ticketed events'
);

-- Should reject attendee registration before the registration window opens
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventRegistrationUpcomingID', :'user1ID'
    ),
    'event registration is not open',
    'Rejects attendee registration before the registration window opens'
);

-- Should reject attendee registration after the registration window closes
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventRegistrationClosedID', :'user7ID'
    ),
    'event registration is not open',
    'Rejects attendee registration after the registration window closes'
);

-- Should reject open-only registration after the event starts
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventRegistrationOpenUntilStartID', :'user7ID'
    ),
    'event registration is not open',
    'Rejects attendee registration after an open-only registration window reaches the event start'
);

-- Should allow manually invited attendees after the registration window closes
select is(
    attend_event(:'communityID'::uuid, :'eventRegistrationClosedID'::uuid, :'user8ID'::uuid),
    'attendee',
    'Allows manually invited attendees to accept after the registration window closes'
);

-- Should allow manually invited attendees after open-only registration reaches event start
select is(
    attend_event(:'communityID'::uuid, :'eventRegistrationOpenUntilStartID'::uuid, :'user9ID'::uuid),
    'attendee',
    'Allows manually invited attendees to accept after an open-only registration window reaches the event start'
);

-- Should create an attendee row after a successful RSVP
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventOKID'::uuid and user_id = :'user1ID'::uuid
        and manually_invited = false
    ),
    'Creates non-manually invited event_attendee row after confirmed RSVP'
);

-- Should discard submitted answers when the event has no registration questions
select is(
    attend_event(
        :'communityID'::uuid,
        :'eventOKID'::uuid,
        :'user4ID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "No question"}]}',
            :'ignoredQuestionID'
        )::jsonb
    ),
    'attendee',
    'Returns attendee when questionless event receives ignored answers'
);

select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventOKID'::uuid
        and user_id = :'user4ID'::uuid
    ),
    null::jsonb,
    'Does not store answers for a questionless event'
);

-- Should allow attendance for a capacity-limited event with an open seat
select is(
    attend_event(:'communityID'::uuid, :'eventFullNoWaitlistID'::uuid, :'user2ID'::uuid),
    'attendee',
    'Returns attendee when a capacity-limited event still has room'
);

-- Should reject RSVP when the event is full and waitlist is disabled
select is(
    attend_event(
        :'communityID'::uuid,
        :'eventFullNoWaitlistID'::uuid,
        :'user3ID'::uuid
    ),
    'event-capacity-unavailable',
    'Rejects new RSVP when the event is sold out and waitlist is disabled'
);

-- Should apply capacity checks when a canceled attendee rejoins
select is(
    attend_event(
        :'communityID'::uuid,
        :'eventFullNoWaitlistID'::uuid,
        :'user7ID'::uuid
    ),
    'event-capacity-unavailable',
    'Rejects a canceled attendee rejoin when the event is sold out'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventFullNoWaitlistID'::uuid
        and user_id = :'user7ID'::uuid
    ),
    'attendance-canceled',
    'Preserves canceled attendance after a sold-out rejoin is rejected'
);

-- Should reject duplicate RSVP for a confirmed attendee
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventFullNoWaitlistID', :'user1ID'
    ),
    'user is already attending this event',
    'Rejects duplicate RSVP for a confirmed attendee'
);

-- Should confirm a pending organizer invitation even when the event is full
select is(
    attend_event(:'communityID'::uuid, :'eventFullNoWaitlistID'::uuid, :'user5ID'::uuid),
    'attendee',
    'Returns attendee when accepting a pending organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventFullNoWaitlistID'::uuid
        and user_id = :'user5ID'::uuid
    ),
    'confirmed',
    'Converts the pending organizer invitation into confirmed attendance'
);

select ok(
    (
        select manually_invited
        from event_attendee
        where event_id = :'eventFullNoWaitlistID'::uuid
        and user_id = :'user5ID'::uuid
    ),
    'Keeps accepted organizer invitations marked as manually invited'
);

-- Should confirm a rejected organizer invitation even when the event is full
select is(
    attend_event(:'communityID'::uuid, :'eventFullNoWaitlistID'::uuid, :'user6ID'::uuid),
    'attendee',
    'Returns attendee when reversing a rejected organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventFullNoWaitlistID'::uuid
        and user_id = :'user6ID'::uuid
    ),
    'confirmed',
    'Converts the rejected organizer invitation into confirmed attendance'
);

-- Should allow RSVP after an organizer invitation was canceled
select is(
    attend_event(:'communityID'::uuid, :'eventOKID'::uuid, :'user3ID'::uuid),
    'attendee',
    'Returns attendee after a canceled organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventOKID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'confirmed',
    'Converts the canceled organizer invitation into confirmed attendance'
);

select ok(
    not (
        select manually_invited
        from event_attendee
        where event_id = :'eventOKID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Clears manually invited when a canceled invitation is reused by a normal RSVP'
);

-- Should place the user on the waitlist when the event is full and waitlist is enabled
select is(
    attend_event(:'communityID'::uuid, :'eventFullWaitlistID'::uuid, :'user2ID'::uuid),
    'waitlisted',
    'Returns waitlisted when the event is full and waitlist is enabled'
);

-- Should create a waitlist row after joining the waitlist
select ok(
    exists(
        select 1
        from event_waitlist
        where event_id = :'eventFullWaitlistID'::uuid and user_id = :'user2ID'::uuid
    ),
    'Creates event_waitlist row after joining the waitlist'
);

-- Should allow waitlist join after an organizer invitation was canceled
select is(
    attend_event(:'communityID'::uuid, :'eventFullWaitlistID'::uuid, :'user3ID'::uuid),
    'waitlisted',
    'Returns waitlisted after a canceled organizer invitation for a full event'
);

select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventFullWaitlistID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Removes the canceled organizer invitation row before waitlisting'
);

select ok(
    exists(
        select 1
        from event_waitlist
        where event_id = :'eventFullWaitlistID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Creates waitlist row after a canceled organizer invitation'
);

-- Should move a canceled attendee to the waitlist when the event is full
select is(
    attend_event(:'communityID'::uuid, :'eventFullWaitlistID'::uuid, :'user4ID'::uuid),
    'waitlisted',
    'Returns waitlisted when a canceled attendee rejoins a full event'
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
    'Moves canceled attendance into the waitlist without a cross-table duplicate'
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

-- Should create only a waitlist row for answerless waitlist joins
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

-- Should recreate attendance when an accepted request no longer has an attendee row
select is(
    attend_event(:'communityID'::uuid, :'eventInviteOnlyID'::uuid, :'user3ID'::uuid),
    'attendee',
    'Returns attendee when an accepted requester rejoins'
);

-- Should create an attendee row for an accepted requester who rejoins
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventInviteOnlyID'::uuid and user_id = :'user3ID'::uuid
    ),
    'Creates attendee row when an accepted requester rejoins'
);

-- Should store answers when an accepted requester rejoins after cancellation
select is(
    attend_event(
        :'questionsCommunityID'::uuid,
        :'eventQuestionsApprovalID'::uuid,
        :'questionsRejoinInsertUserID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "Rejoin answer"}]}',
            :'questionID'
        )::jsonb
    ),
    'attendee',
    'Should allow accepted requesters to rejoin question-enabled events'
);

select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventQuestionsApprovalID'::uuid
        and user_id = :'questionsRejoinInsertUserID'::uuid
    ),
    format(
        '{"answers": [{"question_id": "%s", "value": "Rejoin answer"}]}',
        :'questionID'
    )::jsonb,
    'Should store answers when accepted requesters rejoin after cancellation'
);

-- Should replace stale answers when an accepted requester reuses a canceled row
select is(
    attend_event(
        :'questionsCommunityID'::uuid,
        :'eventQuestionsApprovalID'::uuid,
        :'questionsRejoinConflictUserID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "Updated rejoin answer"}]}',
            :'questionID'
        )::jsonb
    ),
    'attendee',
    'Should allow accepted requesters to reuse canceled attendee rows'
);

select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventQuestionsApprovalID'::uuid
        and user_id = :'questionsRejoinConflictUserID'::uuid
    ),
    format(
        '{"answers": [{"question_id": "%s", "value": "Updated rejoin answer"}]}',
        :'questionID'
    )::jsonb,
    'Should replace stale answers when accepted requesters reuse canceled attendee rows'
);

-- Should create a pending invitation request when approval is required
select is(
    attend_event(:'communityID'::uuid, :'eventInviteOnlyID'::uuid, :'user2ID'::uuid),
    'pending-approval',
    'Returns pending approval when the event requires invitation review'
);

-- Should not create an attendee row before approval
select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventInviteOnlyID'::uuid and user_id = :'user2ID'::uuid
    ),
    'Does not create event_attendee row before invitation approval'
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
    'Creates pending invitation request row'
);

-- Should reject duplicate invitation requests
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInviteOnlyID', :'user2ID'
    ),
    'user has already requested an invitation for this event',
    'Rejects duplicate invitation requests'
);

-- Should reject users whose invitation request was rejected
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInviteOnlyID', :'user4ID'
    ),
    'invitation request was rejected for this event',
    'Rejects users whose invitation request was rejected'
);

-- Should reject duplicate waitlist joins
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventFullWaitlistID', :'user2ID'
    ),
    'user is already on the waiting list for this event',
    'Rejects duplicate waitlist joins'
);

-- Should reject unpublished events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventUnpublishedID', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects unpublished events'
);

-- Should reject canceled events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventCanceledID', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects canceled events'
);

-- Should reject deleted events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventDeletedID', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects deleted events'
);

-- Should reject past events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventPastID', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects past events'
);

-- Should reject events from inactive groups
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInactiveGroupID', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects events from inactive groups'
);

-- Should start registration-question completion from a pending attendee
select is(
    (
        select status
        from event_attendee
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsPendingUserID'::uuid
    ),
    'registration-questions-pending',
    'Should start registration-question completion from a pending attendee'
);

-- Should confirm pending registration-question attendees with valid answers
select is(
    attend_event(
        :'questionsCommunityID'::uuid,
        :'eventQuestionsID'::uuid,
        :'questionsPendingUserID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "Pending answer"}]}',
            :'questionID'
        )::jsonb
    ),
    'attendee',
    'Should confirm pending registration-question attendees with valid answers'
);

-- Should store answers when confirming pending registration-question attendees
select is(
    (
        select jsonb_build_object(
            'registration_answers',
            registration_answers,
            'status',
            status
        )
        from event_attendee
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsPendingUserID'::uuid
    ),
    format(
        '{"registration_answers":{"answers":[{"question_id":"%s","value":"Pending answer"}]},"status":"confirmed"}',
        :'questionID'
    )::jsonb,
    'Should store answers when confirming pending registration-question attendees'
);

-- Should require answers when attending an event with questions
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'questionsCommunityID', :'eventQuestionsID', :'questionsAttendeeUserID'
    ),
    'questionnaire answers are required',
    'Should require answers when attending an event with questions'
);

-- Should attend with valid registration answers
select is(
    attend_event(
        :'questionsCommunityID'::uuid,
        :'eventQuestionsID'::uuid,
        :'questionsAttendeeUserID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "Attendee answer"}]}',
            :'questionID'
        )::jsonb
    ),
    'attendee',
    'Should attend with valid registration answers'
);

-- Should store answers submitted while attending
select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsAttendeeUserID'::uuid
    ),
    format(
        '{"answers": [{"question_id": "%s", "value": "Attendee answer"}]}',
        :'questionID'
    )::jsonb,
    'Should store answers submitted while attending'
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
