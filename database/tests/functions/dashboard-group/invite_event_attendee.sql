-- Tests creating organizer event invitations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(55);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a130000-0000-0000-0000-000000000001'
\set canceledAttendeeUserID '3a130000-0000-0000-0000-000000000019'
\set canceledEventID '3a130000-0000-0000-0000-000000000002'
\set capacityEventID '3a130000-0000-0000-0000-000000000021'
\set capacityInviteUserID '3a130000-0000-0000-0000-000000000022'
\set capacityQueueUserID '3a130000-0000-0000-0000-000000000023'
\set communityID '3a130000-0000-0000-0000-000000000003'
\set confirmedAttendeeUserID '3a130000-0000-0000-0000-000000000004'
\set eventCategoryID '3a130000-0000-0000-0000-000000000005'
\set eventID '3a130000-0000-0000-0000-000000000006'
\set eventQuestionsID '3a130000-0000-0000-0000-000000000007'
\set expiredReservationEventID '3a130000-0000-0000-0000-00000000003f'
\set expiredReservationInviteUserID '3a130000-0000-0000-0000-000000000040'
\set expiredReservationOfferID '3a130000-0000-0000-0000-000000000041'
\set expiredReservationOfferUserID '3a130000-0000-0000-0000-000000000042'
\set expiredReservationPromotedUserID '3a130000-0000-0000-0000-000000000043'
\set groupCategoryID '3a130000-0000-0000-0000-000000000008'
\set groupID '3a130000-0000-0000-0000-000000000009'
\set inProgressEventID '3a130000-0000-0000-0000-000000000025'
\set inProgressInviteUserID '3a130000-0000-0000-0000-000000000026'
\set inProgressPriceWindowID '3a130000-0000-0000-0000-000000000027'
\set inProgressTicketTypeID '3a130000-0000-0000-0000-000000000028'
\set invalidTicketUserID '3a130000-0000-0000-0000-000000000029'
\set paidContextEventID '3a130000-0000-0000-0000-000000000049'
\set paidContextGroupID '3a130000-0000-0000-0000-00000000004a'
\set paidContextInviteUserID '3a130000-0000-0000-0000-00000000004b'
\set paidContextPriceWindowID '3a130000-0000-0000-0000-00000000004c'
\set paidContextTicketTypeID '3a130000-0000-0000-0000-00000000004d'
\set paidReadyEventID '3a130000-0000-0000-0000-00000000004e'
\set paidReadyInviteUserID '3a130000-0000-0000-0000-00000000004f'
\set paidReadyPriceWindowID '3a130000-0000-0000-0000-000000000050'
\set paidReadyTicketTypeID '3a130000-0000-0000-0000-000000000051'
\set paidEventID '3a130000-0000-0000-0000-00000000002a'
\set paidInviteUserID '3a130000-0000-0000-0000-00000000002b'
\set paidPriceWindowID '3a130000-0000-0000-0000-00000000002c'
\set paidTicketTypeID '3a130000-0000-0000-0000-00000000002d'
\set privateSimpleInviteUserID '3a130000-0000-0000-0000-000000000046'
\set privateSimplePriceWindowID '3a130000-0000-0000-0000-000000000047'
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
\set siteID '3a130000-0000-0000-0000-000000000024'
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
\set unpublishedEventID '3a130000-0000-0000-0000-000000000016'
\set unavailableInviteUserID '3a130000-0000-0000-0000-00000000003c'
\set unavailableTicketEventID '3a130000-0000-0000-0000-00000000003d'
\set unavailableTicketTypeID '3a130000-0000-0000-0000-00000000003e'
\set unverifiedUserID '3a130000-0000-0000-0000-000000000017'
\set waitlistedUserID '3a130000-0000-0000-0000-000000000018'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into site (description, site_id, theme, title)
values (
    'Event invitation site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Event Invitation Site'
);

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
);

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Tech', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group owning events without payment readiness
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Group with a valid payment recipient for stored event readiness
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,

    payment_recipient
) values (
    :'paidContextGroupID',
    :'communityID',
    :'groupCategoryID',
    'Paid Context Group',
    'paid-context-group',

    '{
        "provider": "stripe",
        "recipient_id": "acct_paid_invite",
        "seller_display_name": "Paid Invite Fiscal Sponsor"
    }'::jsonb
);

-- Users
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values
    ('hash-actor', 'actor@example.com', true, 'Actor', :'actorID', 'actor'),
    ('hash-canceled-attendee', 'canceled-attendee@example.com', true, 'Canceled', :'canceledAttendeeUserID', 'canceled-attendee'),
    ('hash-capacity-invite', 'capacity-invite@example.com', true, 'Capacity Invite', :'capacityInviteUserID', 'capacity-invite'),
    ('hash-capacity-queue', 'capacity-queue@example.com', true, 'Capacity Queue', :'capacityQueueUserID', 'capacity-queue'),
    ('hash-confirmed', 'confirmed@example.com', true, 'Confirmed', :'confirmedAttendeeUserID', 'confirmed'),
    ('hash-in-progress', 'in-progress@example.com', true, 'In Progress', :'inProgressInviteUserID', 'in-progress'),
    ('hash-invalid-ticket', 'invalid-ticket@example.com', true, 'Invalid Ticket', :'invalidTicketUserID', 'invalid-ticket'),
    ('hash-paid-invite', 'paid-invite@example.com', true, 'Paid Invite', :'paidInviteUserID', 'paid-invite'),
    ('hash-private-simple', 'private-simple@example.com', true, 'Private Simple', :'privateSimpleInviteUserID', 'private-simple'),
    ('hash-queue-conflict', 'queue-conflict@example.com', true, 'Queue Conflict', :'queueConflictInviteUserID', 'queue-conflict'),
    ('hash-queue-conflict-head', 'queue-conflict-head@example.com', true, 'Queue Head', :'queueConflictWaitlistUserID', 'queue-conflict-head'),
    ('hash-queue-offer', 'queue-offer@example.com', true, 'Queue Offer', :'queueOfferUserID', 'queue-offer'),
    ('hash-registered', 'registered@example.com', true, 'Registered', :'registeredUserID', 'registered'),
    ('hash-rejected', 'rejected@example.com', true, 'Rejected', :'rejectedUserID', 'rejected'),
    ('hash-sold-out-invite', 'sold-out-invite@example.com', true, 'Sold Out Invite', :'soldOutInviteUserID', 'sold-out-invite'),
    ('hash-sold-out-occupant', 'sold-out-occupant@example.com', true, 'Sold Out Occupant', :'soldOutOccupantID', 'sold-out-occupant'),
    ('hash-unavailable', 'unavailable-ticket@example.com', true, 'Unavailable Ticket', :'unavailableInviteUserID', 'unavailable-ticket'),
    ('hash-unverified', 'unverified@example.com', false, 'Unverified', :'unverifiedUserID', 'unverified'),
    ('hash-waitlisted', 'waitlisted@example.com', true, 'Waitlisted', :'waitlistedUserID', 'waitlisted'),
    ('hash-rq-invited', 'rq-invited@example.com', true, 'RQ Invited', :'questionsInvitedUserID', 'rq-invited');

-- Invitee used to validate stored paid-event context
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values (
    'hash-paid-context-invite',
    'paid-context-invite@example.com',
    true,
    'Paid Context Invite',
    :'paidContextInviteUserID',
    'paid-context-invite'
);

-- Invitee used by the successful paid snapshot scenario
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values (
    'hash-paid-ready-invite',
    'paid-ready-invite@example.com',
    true,
    'Paid Ready Invite',
    :'paidReadyInviteUserID',
    'paid-ready-invite'
);

-- Users used by expired RSVP reservation reconciliation
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values
    (
        'hash-expired-reservation-invite',
        'expired-reservation-invite@example.com',
        true,
        'Expired Reservation Invite',
        :'expiredReservationInviteUserID',
        'expired-reservation-invite'
    ),
    (
        'hash-expired-reservation-offer',
        'expired-reservation-offer@example.com',
        true,
        'Expired Reservation Offer',
        :'expiredReservationOfferUserID',
        'expired-reservation-offer'
    ),
    (
        'hash-expired-reservation-promoted',
        'expired-reservation-promoted@example.com',
        true,
        'Expired Reservation Promoted',
        :'expiredReservationPromotedUserID',
        'expired-reservation-promoted'
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
    payment_currency_code,
    published,
    canceled,
    starts_at,
    capacity,
    waitlist_enabled
)
values
    (
        :'capacityEventID',
        'Capacity Event',
        'capacity-event',
        'Test queue-priority event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        current_timestamp + interval '1 day',
        1,
        true
    ), (
        :'eventID',
        'Free Event',
        'free-event',
        'Test free event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        current_timestamp + interval '1 day',
        null,
        false
    ), (
        :'canceledEventID',
        'Canceled Event',
        'canceled-event',
        'Test canceled event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'USD',
        true,
        true,
        current_timestamp + interval '1 day',
        null,
        false
    ), (
        :'ticketedEventID',
        'Ticketed Event',
        'ticketed-event',
        'Test ticketed event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        current_timestamp + interval '1 day',
        null,
        false
    ), (
        :'paidEventID',
        'Paid Ticket Event',
        'paid-ticket-event',
        'Test paid ticket event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'USD',
        true,
        false,
        current_timestamp + interval '1 day',
        null,
        false
    ), (
        :'queueConflictEventID',
        'Queue Conflict Ticket Event',
        'queue-conflict-ticket-event',
        'Test ticketed queue-priority event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        current_timestamp + interval '1 day',
        null,
        true
    ), (
        :'queueOfferEventID',
        'Queue Offer Ticket Event',
        'queue-offer-ticket-event',
        'Test ticketed queue-offer event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        current_timestamp + interval '1 day',
        null,
        true
    ), (
        :'soldOutTicketedEventID',
        'Sold Out Ticket Event',
        'sold-out-ticket-event',
        'Test ticketed sold-out event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        current_timestamp + interval '1 day',
        null,
        false
    ), (
        :'unavailableTicketEventID',
        'Unavailable Ticket Event',
        'unavailable-ticket-event',
        'Test unavailable ticket event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        current_timestamp + interval '1 day',
        null,
        false
    ), (
        :'unpublishedEventID',
        'Unpublished Event',
        'unpublished-event',
        'Test unpublished event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'USD',
        false,
        false,
        current_timestamp + interval '1 day',
        null,
        false
    );

-- Paid event with an incomplete stored venue for readiness validation
insert into event (
    event_id,
    canceled,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    timezone,
    waitlist_enabled,

    payment_currency_code,
    starts_at
) values (
    :'paidContextEventID',
    false,
    'Paid event with incomplete venue context',
    :'eventCategoryID',
    'in-person',
    :'paidContextGroupID',
    'Paid Context Event',
    true,
    'paid-context-event',
    'UTC',
    false,

    'USD',
    current_timestamp + interval '1 day'
);

-- Paid event with a complete venue for successful paid invitation snapshots
insert into event (
    event_id,
    canceled,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    timezone,
    waitlist_enabled,

    payment_currency_code,
    starts_at,
    venue_address,
    venue_city,
    venue_country_code,
    venue_name,
    venue_zip_code
) values (
    :'paidReadyEventID',
    false,
    'Paid event with complete venue context',
    :'eventCategoryID',
    'in-person',
    :'paidContextGroupID',
    'Paid Ready Event',
    true,
    'paid-ready-event',
    'UTC',
    false,

    'USD',
    current_timestamp + interval '1 day',
    '1 Main St',
    'Portland',
    'US',
    'Venue',
    '97201'
);

-- RSVP event whose expired reservation is reconciled before organizer invite allocation
insert into event (
    capacity,
    canceled,
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
    timezone,
    waitlist_enabled
) values (
    1,
    false,
    'Test expired reservation reconciliation event',
    :'eventCategoryID',
    :'expiredReservationEventID',
    'in-person',
    :'groupID',
    'Expired Reservation Event',
    null,
    true,
    'expired-reservation-event',
    current_timestamp + interval '1 day',
    'UTC',
    true
);

-- In-progress ticketed event that remains open for organizer invitations
insert into event (
    capacity,
    canceled,
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
    ends_at,
    timezone,
    waitlist_enabled
) values (
    null,
    false,
    'Test in-progress ticketed event',
    :'eventCategoryID',
    :'inProgressEventID',
    'in-person',
    :'groupID',
    'In Progress Ticket Event',
    null,
    true,
    'in-progress-ticket-event',
    current_timestamp - interval '1 hour',
    current_timestamp + interval '2 hours',
    'UTC',
    false
);

-- Event with registration questions before confirmation
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    payment_currency_code,
    published,
    starts_at,
    registration_ends_at,
    registration_questions
)
values (
    :'eventQuestionsID',
    'Questions Event',
    'questions-event',
    'Test event with registration questions',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    current_timestamp + interval '1 day',
    current_timestamp - interval '1 hour',
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'registrationQuestionID'
    )::jsonb
);

-- Ticket types
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values
    (:'inProgressTicketTypeID', :'inProgressEventID', 1, 100, 'In-progress admission'),
    (:'paidTicketTypeID', :'paidEventID', 1, 100, 'Paid admission'),
    (:'queueConflictTicketTypeID', :'queueConflictEventID', 1, 1, 'Queue conflict admission'),
    (:'queueOfferTicketTypeID', :'queueOfferEventID', 1, 1, 'Queue offer admission'),
    (:'soldOutTicketTypeID', :'soldOutTicketedEventID', 1, 1, 'Sold-out admission'),
    (:'ticketTypeID', :'ticketedEventID', 1, 100, 'General'),
    (:'ticketTypeSecondaryID', :'ticketedEventID', 2, 25, 'Secondary admission');

-- Paid ticket tier used to validate stored event readiness
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'paidContextTicketTypeID',
    :'paidContextEventID',
    1,
    100,
    'Paid context admission'
);

-- Paid ticket tier used by the successful paid snapshot scenario
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'paidReadyTicketTypeID',
    :'paidReadyEventID',
    1,
    100,
    'Paid ready admission'
);

-- Inactive ticket type used to reject unavailable ticketed invitations
insert into event_ticket_type (
    active,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    false,
    :'unavailableTicketEventID',
    :'unavailableTicketTypeID',
    1,
    100,
    'Unavailable admission'
);

insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values
    (0, :'inProgressPriceWindowID', :'inProgressTicketTypeID'),
    (2500, :'paidPriceWindowID', :'paidTicketTypeID'),
    (0, :'queueConflictPriceWindowID', :'queueConflictTicketTypeID'),
    (0, :'queueOfferPriceWindowID', :'queueOfferTicketTypeID'),
    (0, :'soldOutPriceWindowID', :'soldOutTicketTypeID'),
    (0, :'ticketPriceWindowID', :'ticketTypeID'),
    (0, :'ticketPriceWindowSecondaryID', :'ticketTypeSecondaryID');

-- Positive ticket price used to exercise paid stored event readiness
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'paidContextPriceWindowID',
    2500,
    :'paidContextTicketTypeID'
);

-- Positive ticket price used by the successful paid snapshot scenario
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'paidReadyPriceWindowID',
    2500,
    :'paidReadyTicketTypeID'
);

-- Events without a specialized ticket fixture use a default free tier
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
)
select
    e.event_id,
    gen_random_uuid(),
    1,
    greatest(coalesce(e.capacity, 100), 1),
    'General Admission'
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free prices for the default ticket tiers
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
)
select 0, gen_random_uuid(), ett.event_ticket_type_id
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

-- Capture the capacity event's synthesized ticket tier
select event_ticket_type_id as "capacityTicketTypeID"
from event_ticket_type
where event_id = :'capacityEventID'
\gset

-- Capture the registration-question event's synthesized ticket tier
select event_ticket_type_id as "eventQuestionsTicketTypeID"
from event_ticket_type
where event_id = :'eventQuestionsID'
\gset

-- Capture the expired-reservation event's synthesized ticket tier
select event_ticket_type_id as "expiredReservationTicketTypeID"
from event_ticket_type
where event_id = :'expiredReservationEventID'
\gset

-- Capture the simple RSVP event's synthesized ticket tier
select event_ticket_type_id as "simpleTicketTypeID"
from event_ticket_type
where event_id = :'eventID'
\gset

-- Existing attendees and invitation decisions
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'confirmedAttendeeUserID', 'confirmed'),
    (:'eventID', :'rejectedUserID', 'invitation-rejected');

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
        (select event_ticket_type_id from event_ticket_type where event_id = :'capacityEventID' limit 1),
        :'capacityQueueUserID'
    ),
    (
        :'eventID',
        (select event_ticket_type_id from event_ticket_type where event_id = :'eventID' limit 1),
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
    (select event_ticket_type_id from event_ticket_type where event_id = :'expiredReservationEventID' limit 1),
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'pending',
    :'expiredReservationOfferUserID'
);

-- RSVP waitlist user promoted when the expired reservation is swept
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'expiredReservationEventID',
    (select event_ticket_type_id from event_ticket_type where event_id = :'expiredReservationEventID' limit 1),
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
        $$ select invite_event_attendee(%L, %L, %L, %L, 'registered@example.com') $$,
        :'actorID', :'groupID', :'eventID', :'registeredUserID'
    ),
    'P0001',
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
            'actor',
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

-- Add a private tier after exercising sole-tier auto-selection
insert into event_ticket_type (
    availability,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    'invitation_only',
    :'eventID',
    :'privateSimpleTicketTypeID',
    2,
    10,
    'Private admission'
);

-- Current free price for the private simple-RSVP tier
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    0,
    :'privateSimplePriceWindowID',
    :'privateSimpleTicketTypeID'
);

-- Should create a private-tier offer on a simple RSVP event
select is(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'eventID',
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
    'P0001',
    'user already has a pending event invitation',
    'Should reject re-inviting users with a pending invitation'
);

-- Should reject re-inviting confirmed attendees
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'eventID', :'confirmedAttendeeUserID', :'simpleTicketTypeID'
    ),
    'P0001',
    'user is already attending this event',
    'Should reject re-inviting confirmed attendees'
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

select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'eventID', :'waitlistedUserID', :'simpleTicketTypeID'
    ),
    'P0001',
    'user already has a pending event invitation',
    'Should reject inviting a user with an active waitlist offer'
);

select is(
    (
        select count(*)
        from event_waitlist
        where event_id = :'eventID'::uuid
        and user_id = :'waitlistedUserID'::uuid
    ),
    0::bigint,
    'Should remove the invited user from the waitlist'
);

-- Should pre-register an email invitee and keep them out of normal registration state
select ok(
    invite_event_attendee(
        :'actorID',
        :'groupID',
        :'eventID',
        null,
        'new@example.com',
        :'simpleTicketTypeID'
    ) is not null,
    'Should invite by email'
);

select is(
    (
        select registration_status
        from "user"
        where email = 'new@example.com'
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
        and u.email = 'new@example.com'
        $$,
        :'eventID'
    ),
    $$
        values (
            'organizer_invitation',
            'pending',
            'new@example.com',
            'pre-registered'
        )
    $$,
    'Should create a pending offer for an email invite'
);

-- Should reject email invites for registered users with unverified email
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, null, 'unverified@example.com', %L) $$,
        :'actorID', :'groupID', :'eventID', :'simpleTicketTypeID'
    ),
    'P0001',
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
    'P0001',
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
    'P0001',
    'ticket type is not available',
    'Should reject unavailable ticket types for event invitations'
);

select is(
    (
        select count(*)::int
        from admission_offer
        where event_id = :'unavailableTicketEventID'::uuid
        and user_id = :'unavailableInviteUserID'::uuid
    ),
    0,
    'Should not create an offer for unavailable ticket types'
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
    'P0001',
    'ticket type is not available',
    'Should reject ticket types selected for a different event'
);

select is(
    (
        select count(*)::int
        from admission_offer
        where event_id = :'eventID'::uuid
        and user_id = :'invalidTicketUserID'::uuid
    ),
    0,
    'Should not create an offer when a tier belongs to a different event'
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
    'P0001',
    'paid-capable events require a payment recipient',
    'Should reject paid ticket invitations when payment readiness fails'
);

select is(
    (
        select count(*)::int
        from admission_offer
        where event_id = :'paidEventID'::uuid
        and user_id = :'paidInviteUserID'::uuid
    ),
    0,
    'Should not create an offer when paid ticket readiness fails'
);

-- Should validate the stored event venue for paid ticket invitations
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L, %L) $$,
        :'actorID',
        :'paidContextGroupID',
        :'paidContextEventID',
        :'paidContextInviteUserID',
        :'paidContextTicketTypeID',
        'stripe'
    ),
    'P0001',
    'paid ticketing requires an in-person or hybrid event with a complete physical venue',
    'Should validate the stored event venue for paid ticket invitations'
);

select is(
    (
        select count(*)::int
        from admission_offer
        where event_id = :'paidContextEventID'::uuid
        and user_id = :'paidContextInviteUserID'::uuid
    ),
    0,
    'Should not create an offer when the stored paid event is ineligible'
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
            'expires_at', extract(epoch from ao.expires_at)::bigint,
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
    'P0001',
    'event not found or inactive',
    'Should reject unpublished events'
);

-- Should reject canceled events
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null, %L) $$,
        :'actorID', :'groupID', :'canceledEventID', :'registeredUserID', :'simpleTicketTypeID'
    ),
    'P0001',
    'event not found or inactive',
    'Should reject canceled events'
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
