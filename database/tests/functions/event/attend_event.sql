-- Tests routing event attendance into checkout, approval, or a ticket waitlist.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(61);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5e020000-0000-0000-0000-000000000001'
\set duplicateWaitlistUserID '5e020000-0000-0000-0000-000000000055'
\set eventCategoryID '5e020000-0000-0000-0000-000000000003'
\set eventFullNoWaitlistID '5e020000-0000-0000-0000-000000000005'
\set eventFullWaitlistID '5e020000-0000-0000-0000-000000000006'
\set eventInviteOnlyID '5e020000-0000-0000-0000-000000000008'
\set eventOKID '5e020000-0000-0000-0000-000000000009'
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
\set ticketExpiredPurchaseID '5e020000-0000-0000-0000-000000000053'
\set ticketExpiredPurchaseUserID '5e020000-0000-0000-0000-000000000054'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_community(:'questionsCommunityID');
select fx_group_category(:'questionsGroupCategoryID', :'questionsCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_event_category(:'questionsEventCategoryID', :'questionsCommunityID');
select fx_user(:'user5ID');
select fx_user(:'user8ID');
select fx_user(:'user9ID');
select fx_user(:'questionsRejoinInsertUserID');
select fx_user(:'questionsRejoinConflictUserID');
select fx_user(:'questionsPendingUserID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_user(:'user4ID');
select fx_user(:'user6ID');
select fx_user(:'user7ID');
select fx_user(:'user10ID');
select fx_user(:'duplicateWaitlistUserID');
select fx_user(:'activeApprovalOfferUserID');
select fx_user(:'activeApprovalPurchaseUserID');
select fx_user(:'ticketAvailableUserID');
select fx_user(:'ticketPrivateSelectionUserID');
select fx_user(:'ticketSoldOutNoWaitlistHolderUserID');
select fx_user(:'ticketSoldOutNoWaitlistUserID');
select fx_user(:'ticketWaitlistActivePurchaseUserID');
select fx_user(:'ticketExpiredPurchaseUserID');
select fx_user(:'questionsWaitlistUserID');
select fx_user(:'questionsSeatUserID');
select fx_user(:'questionsRequestUserID');
select fx_group(:'questionsGroupID', :'questionsCommunityID', :'questionsGroupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

select fx_user(:'questionsAttendeeUserID', jsonb_build_object('name', 'Attendee'));

-- Events with scenario-specific state
select fx_event(:'eventOKID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'OK',
    'published', true,
    'slug', 'ok'
));
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Unpublished',
    'slug', 'unpublished'
));
select fx_event(:'eventFullNoWaitlistID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 2,
    'published', true
));
select fx_event(:'eventFullWaitlistID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'waitlist_enabled', true
));
select fx_event(:'eventInviteOnlyID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'capacity', 1,
    'published', true
));
select fx_event(:'eventRegistrationClosedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'registration_ends_at', current_timestamp - interval '1 hour',
    'starts_at', '2030-01-04 10:00:00+00'
));
select fx_event(:'eventRegistrationUpcomingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'registration_ends_at', current_timestamp + interval '2 days',
    'registration_starts_at', current_timestamp + interval '1 day',
    'starts_at', '2030-01-05 10:00:00+00'
));
select fx_event(:'eventRegistrationOpenUntilStartID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 hour',
    'published', true,
    'registration_starts_at', current_timestamp - interval '2 hours',
    'starts_at', current_timestamp - interval '1 hour'
));
select fx_event(:'eventReactivationID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Reactivation',
    'published', true
));

-- Ticketed event used to reject direct RSVP enrollment
select fx_event(:'eventTicketedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Ticketed',
    'published', true,
    'waitlist_enabled', true
));
select fx_event(:'eventTicketApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));
select fx_event(:'eventTicketPrivateApprovalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));

-- Ticketed events used by private-request and waitlist failure branches
select fx_event(:'eventTicketAvailableID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'waitlist_enabled', true
));
select fx_event(:'eventTicketPrivateSelectionID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));
select fx_event(:'eventTicketSoldOutNoWaitlistID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'eventTicketWaitlistActivePurchaseID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'waitlist_enabled', true
));

select fx_event_ticket_type(:'ticketTypeID', :'eventTicketedID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'ticketSecondTypeID', :'eventTicketedID', jsonb_build_object(
    'order', 2,
    'seats_total', 1
));
select fx_event_ticket_type(:'ticketApprovalTypeID', :'eventTicketApprovalID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'ticketPrivateApprovalTypeID', :'eventTicketPrivateApprovalID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 10
));
select fx_event_ticket_type(:'ticketPrivateTypeID', :'eventTicketedID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 3,
    'seats_total', 1
));

-- Ticket tiers used by private-request and waitlist failure branches
select fx_event_ticket_type(:'ticketAvailableTypeID', :'eventTicketAvailableID', jsonb_build_object('seats_total', 2));
select fx_event_ticket_type(:'ticketPrivateSelectionTypeID', :'eventTicketPrivateSelectionID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 10
));
select fx_event_ticket_type(:'ticketSoldOutNoWaitlistTypeID', :'eventTicketSoldOutNoWaitlistID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'ticketWaitlistActivePurchaseTypeID', :'eventTicketWaitlistActivePurchaseID', jsonb_build_object('seats_total', 1));

select fx_event_ticket_price_window(:'ticketPriceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'ticketApprovalPriceWindowID', :'ticketApprovalTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'ticketPrivateApprovalPriceWindowID', :'ticketPrivateApprovalTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'ticketSecondPriceWindowID', :'ticketSecondTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'ticketPrivatePriceWindowID', :'ticketPrivateTypeID', jsonb_build_object('amount_minor', 0));

-- Current prices used by private-request and waitlist failure branch tiers
select fx_event_ticket_price_window(:'ticketAvailablePriceWindowID', :'ticketAvailableTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'ticketPrivateSelectionPriceWindowID', :'ticketPrivateSelectionTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'ticketSoldOutNoWaitlistPriceWindowID', :'ticketSoldOutNoWaitlistTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'ticketWaitlistActivePurchasePriceWindowID', :'ticketWaitlistActivePurchaseTypeID', jsonb_build_object('amount_minor', 0));

-- Events requiring registration answers during attendance
select fx_event(:'eventQuestionsID', :'questionsGroupID', :'questionsEventCategoryID', jsonb_build_object(
    'published', true,
    'registration_questions', format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    'starts_at', '2030-01-01 10:00:00+00'
));
select fx_event(:'eventQuestionsApprovalID', :'questionsGroupID', :'questionsEventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true,
    'registration_questions', format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    'starts_at', '2030-01-02 10:00:00+00'
));
select fx_event(:'eventQuestionsFullWaitlistID', :'questionsGroupID', :'questionsEventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'registration_questions', format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    'starts_at', '2030-01-03 10:00:00+00',
    'waitlist_enabled', true
));

-- Events without a specialized ticket fixture use a default free tier
select fx_event_ticket_type(gen_random_uuid(), e.event_id, jsonb_build_object(
    'seats_total', greatest(coalesce(e.capacity, 100), 1)
))
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free prices for the default ticket tiers
select fx_event_ticket_price_window(gen_random_uuid(), ett.event_ticket_type_id, jsonb_build_object('amount_minor', 0))
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

-- Event attendees
insert into event_attendee (event_id, user_id, status)
values
    (:'eventFullNoWaitlistID', :'user1ID', 'confirmed'),
    (:'eventFullWaitlistID', :'user1ID', 'confirmed'),
    (:'eventQuestionsFullWaitlistID', :'questionsSeatUserID', 'confirmed');

-- Confirmed attendees own capacity through completed purchases
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
)
select
    0,
    null,
    0,
    ea.event_id,
    ett.event_ticket_type_id,
    'completed',
    ett.title,
    ea.user_id
from event_attendee ea
join lateral (
    select ett.event_ticket_type_id, ett.title
    from event_ticket_type ett
    where ett.event_id = ea.event_id
    order by ett."order", ett.event_ticket_type_id
    limit 1
) ett on true
where ea.status = 'confirmed';

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

-- Existing organizer invitation decisions
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'eventOKID', :'user3ID', true, 'invitation-canceled'),
    (:'eventFullWaitlistID', :'user3ID', false, 'invitation-canceled'),
    (:'eventFullNoWaitlistID', :'user6ID', true, 'invitation-rejected'),
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
        (select event_ticket_type_id from event_ticket_type where event_id = :'eventInviteOnlyID' limit 1),
        :'user3ID',
        '2024-01-01 00:00:00+00',
        'accepted',
        '2024-01-01 01:00:00+00',
        :'user1ID'
    ),
    (
        :'eventInviteOnlyID',
        (select event_ticket_type_id from event_ticket_type where event_id = :'eventInviteOnlyID' limit 1),
        :'user4ID',
        '2024-01-02 00:00:00+00',
        'rejected',
        '2024-01-02 01:00:00+00',
        :'user1ID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should prepare checkout without rewriting canceled attendance history
select is(
    attend_event(:'communityID'::uuid, :'eventReactivationID'::uuid, :'user10ID'::uuid),
    'pending-payment',
    'Should prepare checkout for a user with canceled attendance history'
);

-- Should preserve canceled attendance metadata until checkout completes
select results_eq(
    format($$
        select
            attendance_canceled_at is not null,
            attendance_canceled_by_user_id,
            status
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventReactivationID', :'user10ID'),
    format(
        $$ values (true, %L::uuid, 'attendance-canceled'::text) $$,
        :'user10ID'
    ),
    'Should preserve canceled attendance metadata before checkout'
);

-- Should send direct enrollment through checkout when capacity allows
select is(
    attend_event(:'communityID'::uuid, :'eventOKID'::uuid, :'user1ID'::uuid),
    'pending-payment',
    'Returns pending payment before the free checkout completion step'
);

-- Should require a tier when the event cannot auto-select one
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventTicketedID', :'user2ID'
    ),
    'OCG01',
    'ticket type is required',
    'Requires a selected ticket tier'
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
    'Should create a request for the sole public tier'
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
    'Should retain the selected waitlist ticket tier'
);

-- Should make duplicate joins to the same tier idempotent
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
    'Should retain waitlist FIFO priority after a duplicate join'
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
    'OCG01',
    'ticket type is required',
    'Should reject invitation-only ticket waitlist joins'
);

-- Should reject confirming an unpaid ticket checkout through direct RSVP
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventTicketedID', :'user10ID'
    ),
    'OCG01',
    'user already has an active purchase for this event',
    'Rejects a second enrollment attempt with an active checkout'
);

-- Should reject attendee registration before the registration window opens
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventRegistrationUpcomingID', :'user1ID'
    ),
    'OCG01',
    'event registration is not open',
    'Rejects attendee registration before the registration window opens'
);

-- Should reject attendee registration after the registration window closes
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventRegistrationClosedID', :'user7ID'
    ),
    'OCG01',
    'event registration is not open',
    'Rejects attendee registration after the registration window closes'
);

-- Should reject open-only registration after the event starts
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventRegistrationOpenUntilStartID', :'user7ID'
    ),
    'OCG01',
    'event registration is not open',
    'Rejects attendee registration after an open-only registration window reaches the event start'
);

-- Should not create attendance before checkout completes
select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventOKID'::uuid and user_id = :'user1ID'::uuid
    ),
    'Does not create event_attendee before checkout'
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
    'pending-payment',
    'Returns pending payment when questionless event receives ignored answers'
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
    'pending-payment',
    'Returns pending payment when a capacity-limited event still has room'
);

-- Simulate the checkout completion that consumes the final seat
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
)
select
    0,
    null,
    0,
    ett.event_id,
    ett.event_ticket_type_id,
    'completed',
    ett.title,
    :'user2ID'
from event_ticket_type ett
where ett.event_id = :'eventFullNoWaitlistID';

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
    'OCG01',
    'user is already attending this event',
    'Rejects duplicate RSVP for a confirmed attendee'
);

-- Should apply capacity checks after a rejected organizer invitation
select is(
    attend_event(:'communityID'::uuid, :'eventFullNoWaitlistID'::uuid, :'user6ID'::uuid),
    'event-capacity-unavailable',
    'Returns unavailable capacity after a rejected organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventFullNoWaitlistID'::uuid
        and user_id = :'user6ID'::uuid
    ),
    'invitation-rejected',
    'Preserves rejected organizer invitation history'
);

-- Should allow RSVP after an organizer invitation was canceled
select is(
    attend_event(:'communityID'::uuid, :'eventOKID'::uuid, :'user3ID'::uuid),
    'pending-payment',
    'Returns pending payment after a canceled organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventOKID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'invitation-canceled',
    'Preserves canceled organizer invitation history before checkout'
);

select ok(
    (
        select manually_invited
        from event_attendee
        where event_id = :'eventOKID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Preserves manually invited metadata before checkout'
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

-- Should require accepted requests to continue through their admission offer
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInviteOnlyID', :'user3ID'
    ),
    'OCG01',
    'invitation request was already accepted for this event',
    'Rejects a new enrollment attempt for an accepted request'
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
    'OCG01',
    'user has already requested an invitation for this event',
    'Rejects duplicate invitation requests'
);

-- Should reject users whose invitation request was rejected
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInviteOnlyID', :'user4ID'
    ),
    'OCG01',
    'invitation request was rejected for this event',
    'Rejects users whose invitation request was rejected'
);

-- Should keep duplicate waitlist joins idempotent
select is(
    attend_event(:'communityID'::uuid, :'eventFullWaitlistID'::uuid, :'user2ID'::uuid),
    'waitlisted',
    'Keeps duplicate waitlist joins idempotent'
);

-- Should reject unpublished events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventUnpublishedID', :'user1ID'
    ),
    'OCG01',
    'event not found or inactive',
    'Rejects unpublished events'
);

-- The handler validates questions before the checkout route
select is(
    attend_event(
        :'questionsCommunityID'::uuid,
        :'eventQuestionsID'::uuid,
        :'questionsAttendeeUserID'::uuid
    ),
    'pending-payment',
    'Routes an event with questions into checkout'
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
    'pending-payment',
    'Routes valid registration answers into checkout'
);

-- Should store answers submitted while attending
select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsAttendeeUserID'::uuid
    ),
    null::jsonb,
    'Does not create attendance before checkout stores answers'
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
