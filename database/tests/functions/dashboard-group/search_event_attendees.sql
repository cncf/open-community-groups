-- Tests searching organizer event attendees and invitation offers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(40);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set abandonedCheckoutPurchaseID '3a2e0000-0000-0000-0000-000000000061'
\set abandonedCheckoutUserID '3a2e0000-0000-0000-0000-000000000062'
\set attendanceFilterEventID '3a2e0000-0000-0000-0000-000000000030'
\set attendanceFilterTicketTypeID '3a2e0000-0000-0000-0000-00000000008d'
\set canceledInvitationOfferID '3a2e0000-0000-0000-0000-000000000067'
\set communityID '3a2e0000-0000-0000-0000-000000000001'
\set event1ID '3a2e0000-0000-0000-0000-000000000002'
\set event2ID '3a2e0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a2e0000-0000-0000-0000-000000000004'
\set eventDiscountCode1ID '3a2e0000-0000-0000-0000-000000000005'
\set eventExternalID '3a2e0000-0000-0000-0000-000000000070'
\set eventExternalTicketTypeID '3a2e0000-0000-0000-0000-000000000071'
\set eventPendingCheckoutID '3a2e0000-0000-0000-0000-000000000026'
\set eventPurchase1ID '3a2e0000-0000-0000-0000-000000000006'
\set eventPurchase2ID '3a2e0000-0000-0000-0000-000000000007'
\set eventPurchasePendingCheckoutID '3a2e0000-0000-0000-0000-000000000025'
\set eventQuestionsID '3a2e0000-0000-0000-0000-000000000008'
\set eventQuestionsTicketTypeID '3a2e0000-0000-0000-0000-00000000008e'
\set eventRefundRequest2ID '3a2e0000-0000-0000-0000-000000000009'
\set eventStopwordSearchID '3a2e0000-0000-0000-0000-000000000028'
\set eventStopwordSearchTicketTypeID '3a2e0000-0000-0000-0000-00000000008f'
\set eventTicketType1ID '3a2e0000-0000-0000-0000-000000000010'
\set eventTicketType2ID '3a2e0000-0000-0000-0000-000000000011'
\set eventTicketTypePendingCheckoutID '3a2e0000-0000-0000-0000-000000000027'
\set expiredInvitationOfferID '3a2e0000-0000-0000-0000-000000000065'
\set externalCompletedPurchaseID '3a2e0000-0000-0000-0000-000000000072'
\set externalCompletedUserID '3a2e0000-0000-0000-0000-000000000073'
\set externalMarkedByUserID '3a2e0000-0000-0000-0000-000000000074'
\set externalOfferAdmissionOfferID '3a2e0000-0000-0000-0000-000000000077'
\set externalOfferPurchaseID '3a2e0000-0000-0000-0000-000000000078'
\set externalOfferUserID '3a2e0000-0000-0000-0000-000000000079'
\set externalPendingPurchaseID '3a2e0000-0000-0000-0000-000000000075'
\set externalPendingUserID '3a2e0000-0000-0000-0000-000000000076'
\set externalReplacementPurchaseID '3a2e0000-0000-0000-0000-00000000007a'
\set externalReplacementUserID '3a2e0000-0000-0000-0000-00000000007b'
\set externalReregisterPurchaseID '3a2e0000-0000-0000-0000-00000000007c'
\set externalReregisterUserID '3a2e0000-0000-0000-0000-00000000007d'
\set focusedEligibleUserID '3a2e0000-0000-0000-0000-000000000089'
\set focusedEventID '3a2e0000-0000-0000-0000-00000000008a'
\set focusedOwnerMutedUserID '3a2e0000-0000-0000-0000-00000000008b'
\set focusedTicketTypeID '3a2e0000-0000-0000-0000-000000000090'
\set focusedUnrelatedMutedUserID '3a2e0000-0000-0000-0000-00000000008c'
\set group2ID '3a2e0000-0000-0000-0000-000000000012'
\set groupCategoryID '3a2e0000-0000-0000-0000-000000000013'
\set groupID '3a2e0000-0000-0000-0000-000000000014'
\set lapsedExternalHoldEventID '3a2e0000-0000-0000-0000-000000000091'
\set lapsedExternalHoldPurchaseID '3a2e0000-0000-0000-0000-000000000092'
\set lapsedExternalHoldTicketTypeID '3a2e0000-0000-0000-0000-000000000093'
\set lapsedExternalHoldUserID '3a2e0000-0000-0000-0000-000000000094'
\set missingEventID '3a2e0000-0000-0000-0000-000000000015'
\set pendingCheckoutUserID '3a2e0000-0000-0000-0000-000000000024'
\set pendingInvitationOfferID '3a2e0000-0000-0000-0000-000000000063'
\set progressAwaitingPurchaseID '3a2e0000-0000-0000-0000-000000000040'
\set progressRecoveryJobID '3a2e0000-0000-0000-0000-000000000081'
\set progressRecoveryPurchaseID '3a2e0000-0000-0000-0000-000000000041'
\set progressRecoveryRefundID '3a2e0000-0000-0000-0000-000000000052'
\set progressRefundedJobID '3a2e0000-0000-0000-0000-000000000080'
\set progressRefundedPurchaseID '3a2e0000-0000-0000-0000-000000000042'
\set progressRefundedRefundID '3a2e0000-0000-0000-0000-000000000051'
\set progressRetryJobID '3a2e0000-0000-0000-0000-000000000083'
\set progressRetryPurchaseID '3a2e0000-0000-0000-0000-000000000045'
\set progressRetryRefundID '3a2e0000-0000-0000-0000-000000000054'
\set questionsAttendeeUserID '3a2e0000-0000-0000-0000-000000000016'
\set questionsInvitationOfferID '3a2e0000-0000-0000-0000-000000000066'
\set rankingConfirmedEventID '3a2e0000-0000-0000-0000-000000000095'
\set rankingConfirmedOfferID '3a2e0000-0000-0000-0000-000000000096'
\set rankingConfirmedTicketTypeID '3a2e0000-0000-0000-0000-000000000097'
\set rankingConfirmedUserID '3a2e0000-0000-0000-0000-000000000098'
\set rankingQuestionsEventID '3a2e0000-0000-0000-0000-000000000099'
\set rankingQuestionsOfferID '3a2e0000-0000-0000-0000-00000000009a'
\set rankingQuestionsTicketTypeID '3a2e0000-0000-0000-0000-00000000009b'
\set rankingQuestionsUserID '3a2e0000-0000-0000-0000-00000000009c'
\set refundProgressEventID '3a2e0000-0000-0000-0000-000000000031'
\set refundProgressTicketTypeID '3a2e0000-0000-0000-0000-000000000032'
\set registrationQuestionID '3a2e0000-0000-0000-0000-000000000017'
\set rejectedInvitationOfferID '3a2e0000-0000-0000-0000-000000000064'
\set user1ID '3a2e0000-0000-0000-0000-000000000018'
\set user2ID '3a2e0000-0000-0000-0000-000000000019'
\set user3ID '3a2e0000-0000-0000-0000-000000000020'
\set user4ID '3a2e0000-0000-0000-0000-000000000021'
\set user5ID '3a2e0000-0000-0000-0000-000000000022'
\set user6ID '3a2e0000-0000-0000-0000-000000000023'
\set userStopwordSearchID '3a2e0000-0000-0000-0000-000000000029'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the groups, categories and events
select fx_community(:'communityID');

-- Users exercising abandoned checkout, external offer and refund progress rows
select fx_user(:'abandonedCheckoutUserID');
select fx_user(:'externalOfferUserID');
select fx_user(:'externalReplacementUserID');
select fx_user(:'externalReregisterUserID');
select fx_user(:'pendingCheckoutUserID');

-- Users
select fx_user(:'user1ID', jsonb_build_object(
    'bio', 'Maintains event infrastructure',
    'company', 'Cloud Corp',
    'email', 'alice-search-event-attendees@example.com',
    'github_url', 'https://github.com/alice',
    'name', 'Alice',
    'photo_url', 'https://example.com/alice.png',
    'provider', '{"github": {"username": "alice-gh", "private": "secret"}, "linuxfoundation": {"username": "alice-lf", "subject": "secret"}}'::jsonb,
    'title', 'Principal Engineer',
    'username', 'alice-search-event-attendees',
    'website_url', 'https://example.com/alice'
));
select fx_user(:'user2ID', jsonb_build_object(
    'email', 'bob@example.com',
    'photo_url', 'https://example.com/bob.png',
    'username', 'bob-search-event-attendees'
));
select fx_user(:'user3ID', jsonb_build_object(
    'email', 'pending@example.com',
    'email_verified', false,
    'name', 'Pending Invite',
    'registration_status', 'pre-registered',
    'username', 'pending-search-event-attendees'
));
select fx_user(:'user4ID', jsonb_build_object(
    'email', 'rejected@example.com',
    'name', 'Rejected Invite',
    'username', 'rejected-search-event-attendees'
));
select fx_user(:'user5ID', jsonb_build_object(
    'email', 'canceled@example.com',
    'name', 'Canceled Invite',
    'username', 'canceled'
));
select fx_user(:'user6ID', jsonb_build_object(
    'email', 'questions-pending@example.com',
    'name', 'Questions Pending',
    'username', 'questions-pending-search-event-attendees'
));
select fx_user(:'questionsAttendeeUserID', jsonb_build_object('email_verified', false));
select fx_user(:'userStopwordSearchID', jsonb_build_object('username', 'may'));
select fx_user(:'focusedEligibleUserID');
select fx_user(:'focusedOwnerMutedUserID');
select fx_user(:'focusedUnrelatedMutedUserID');

-- Users used by external payment-pending and completed attendee search rows
select fx_user(:'externalCompletedUserID', jsonb_build_object(
    'email', 'external-completed@example.com',
    'username', 'external-completed'
));
select fx_user(:'externalMarkedByUserID', jsonb_build_object('username', 'external-marked-by'));
select fx_user(:'externalPendingUserID', jsonb_build_object(
    'email', 'external-pending@example.com',
    'username', 'external-pending'
));

-- User whose active attendance predates a declined organizer offer
select fx_user(:'rankingConfirmedUserID');

-- User whose pending registration questions predate an expired organizer offer
select fx_user(:'rankingQuestionsUserID');

-- User holding a lapsed external hold without attendance
select fx_user(:'lapsedExternalHoldUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'General'));

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Organizer messages opt-out used by attendee email eligibility
insert into user_notification_opt_out (notification_category_id, user_id)
values ('organizer-messages', :'user2ID');

-- Owner group and unrelated group
select fx_group(:'group2ID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true
));
select fx_event(:'eventPendingCheckoutID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true
));
select fx_event(:'eventStopwordSearchID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true
));
select fx_event(:'focusedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true
));
select fx_event(:'attendanceFilterEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true
));
select fx_event(:'refundProgressEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'payment_currency_code', 'USD',
    'published', true
));

-- Event with registration questions used to return attendee answers
select fx_event(:'eventQuestionsID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'registration_questions', jsonb_build_array(jsonb_build_object(
                'id', :'registrationQuestionID',
                'kind', 'free-text',
                'options', jsonb_build_array(),
                'prompt', 'Note',
                'required', true
            )),
    'starts_at', '2030-01-01 10:00:00+00'
));

-- External-marked event exposing payment-pending and externally paid attendees
select fx_event(:'eventExternalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/search',
    'published', true,
    'starts_at', '2030-01-01 10:00:00+00'
));

-- External-marked event whose only enrollment is a lapsed external hold
select fx_event(:'lapsedExternalHoldEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/lapsed',
    'published', true,
    'starts_at', '2030-01-01 10:00:00+00'
));

-- Event ranking active attendance against a newer declined offer
select fx_event(:'rankingConfirmedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true
));

-- Event ranking pending registration questions against a newer expired offer
select fx_event(:'rankingQuestionsEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true
));

-- Owner group mute excluding one focused attendee from organizer email
insert into user_group_notification_mute (group_id, user_id)
values (:'groupID', :'focusedOwnerMutedUserID');

-- Unrelated group mute that should not exclude the focused attendee
insert into user_group_notification_mute (group_id, user_id)
values (:'group2ID', :'focusedUnrelatedMutedUserID');

-- Attendees
insert into event_attendee (
    event_id,
    user_id,
    checked_in,
    checked_in_at,
    created_at,
    manually_invited,
    status
) values (
    :'event1ID',
    :'user1ID',
    true,
    '2024-01-01 10:00:00+00',
    '2024-01-01 00:00:00+00',
    true,
    'confirmed'
), (
    :'event1ID',
    :'user2ID',
    false,
    null,
    '2024-01-02 00:00:00+00',
    false,
    'confirmed'
), (
    :'event1ID',
    :'user5ID',
    false,
    null,
    '2024-01-05 00:00:00+00',
    true,
    'invitation-canceled'
), (
    :'event1ID',
    :'user6ID',
    false,
    null,
    '2024-01-06 00:00:00+00',
    false,
    'registration-questions-pending'
), (
    :'eventPendingCheckoutID',
    :'pendingCheckoutUserID',
    false,
    null,
    '2024-01-07 00:00:00+00',
    false,
    'registration-questions-pending'
), (
    :'event2ID',
    :'user2ID',
    true,
    '2024-01-03 15:00:00+00',
    '2024-01-03 00:00:00+00',
    false,
    'confirmed'
), (
    :'eventStopwordSearchID',
    :'userStopwordSearchID',
    false,
    null,
    '2024-01-08 00:00:00+00',
    false,
    'confirmed'
);

-- Attendees used by focused notification preference eligibility checks
insert into event_attendee (event_id, status, user_id)
values
    (:'focusedEventID', 'confirmed', :'focusedEligibleUserID'),
    (:'focusedEventID', 'confirmed', :'focusedOwnerMutedUserID'),
    (:'focusedEventID', 'confirmed', :'focusedUnrelatedMutedUserID');

-- Attendee with registration answers returned by attendee search
insert into event_attendee (event_id, user_id, status, registration_answers)
values (
    :'eventQuestionsID',
    :'questionsAttendeeUserID',
    'confirmed',
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', :'registrationQuestionID',
            'value', 'Attendee answer'
        ))
    )
);

-- Active and canceled attendees used to verify attendance filters
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values
    (null, null, :'attendanceFilterEventID', 'confirmed', :'user1ID'),
    (current_timestamp, :'user2ID', :'attendanceFilterEventID', 'attendance-canceled', :'user2ID');

-- Canceled attendees exposing refund progress and abandoned checkout states
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values
    (current_timestamp, :'abandonedCheckoutUserID', :'refundProgressEventID', 'attendance-canceled', :'abandonedCheckoutUserID'),
    (current_timestamp, :'user1ID', :'refundProgressEventID', 'attendance-canceled', :'user1ID'),
    (current_timestamp, :'user2ID', :'refundProgressEventID', 'attendance-canceled', :'user2ID'),
    (current_timestamp, :'user3ID', :'refundProgressEventID', 'attendance-canceled', :'user3ID'),
    (current_timestamp, :'user6ID', :'refundProgressEventID', 'attendance-canceled', :'user6ID');

-- Confirmed attendee holding the completed external purchase
insert into event_attendee (
    created_at,
    event_id,
    status,
    user_id
) values (
    '2024-01-09 00:00:00+00',
    :'eventExternalID',
    'confirmed',
    :'externalCompletedUserID'
);

-- Previously canceled attendee who later reserved a new external hold
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    created_at,
    event_id,
    status,
    user_id
) values (
    '2024-01-07 00:00:00+00',
    :'externalReregisterUserID',
    '2024-01-07 00:00:00+00',
    :'eventExternalID',
    'attendance-canceled',
    :'externalReregisterUserID'
);

-- Confirmed attendee who also holds a pending replacement purchase
insert into event_attendee (
    created_at,
    event_id,
    status,
    user_id
) values (
    '2024-01-09 12:00:00+00',
    :'eventExternalID',
    'confirmed',
    :'externalReplacementUserID'
);

-- Checked-in attendance revived to confirmed before the declined organizer offer
insert into event_attendee (
    checked_in,
    checked_in_at,
    created_at,
    event_id,
    status,
    user_id
) values (
    true,
    '2024-02-03 10:00:00+00',
    '2024-02-01 00:00:00+00',
    :'rankingConfirmedEventID',
    'confirmed',
    :'rankingConfirmedUserID'
);

-- Pending registration questions created before the expired organizer offer
insert into event_attendee (created_at, event_id, status, user_id)
values ('2024-02-01 00:00:00+00', :'rankingQuestionsEventID', 'registration-questions-pending', :'rankingQuestionsUserID');

-- Discount codes
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    event_id,
    kind,
    title
)
values (
    :'eventDiscountCode1ID',
    500,
    'SAVE5',
    :'event1ID',
    'fixed_amount',
    'Launch discount'
);

-- Ticket types
select fx_event_ticket_type(:'eventTicketType1ID', :'event1ID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General admission'
));
select fx_event_ticket_type(:'eventTicketType2ID', :'event2ID', jsonb_build_object(
    'seats_total', 100,
    'title', 'VIP'
));
select fx_event_ticket_type(:'eventTicketTypePendingCheckoutID', :'eventPendingCheckoutID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General admission'
));
select fx_event_ticket_type(:'refundProgressTicketTypeID', :'refundProgressEventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'Refund progress'
));

-- Admission tiers for events whose ticket details are not under test
select fx_event_ticket_type(:'attendanceFilterTicketTypeID', :'attendanceFilterEventID');
select fx_event_ticket_type(:'eventQuestionsTicketTypeID', :'eventQuestionsID');
select fx_event_ticket_type(:'eventStopwordSearchTicketTypeID', :'eventStopwordSearchID');
select fx_event_ticket_type(:'focusedTicketTypeID', :'focusedEventID');

-- Ticket type for the external attendee search event
select fx_event_ticket_type(:'eventExternalTicketTypeID', :'eventExternalID', jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket type for the lapsed external hold event
select fx_event_ticket_type(:'lapsedExternalHoldTicketTypeID', :'lapsedExternalHoldEventID');

-- Ticket type for the declined offer ranking event
select fx_event_ticket_type(:'rankingConfirmedTicketTypeID', :'rankingConfirmedEventID');

-- Ticket type for the expired offer ranking event
select fx_event_ticket_type(:'rankingQuestionsTicketTypeID', :'rankingQuestionsEventID');

-- Organizer invitation offers
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'canceledInvitationOfferID',
    null,
    '2024-01-10 00:00:00+00',
    null,
    null,
    :'eventQuestionsID',
    :'eventQuestionsTicketTypeID',
    '2024-01-11 00:00:00+00',
    'organizer_invitation',
    'canceled',
    null,
    :'user2ID'
), (
    :'pendingInvitationOfferID',
    2500,
    '2024-01-03 00:00:00+00',
    'USD',
    0,
    :'event1ID',
    :'eventTicketType1ID',
    '2099-01-03 00:00:00+00',
    'organizer_invitation',
    'checkout_pending',
    'General admission',
    :'user3ID'
), (
    :'rejectedInvitationOfferID',
    null,
    '2024-01-04 00:00:00+00',
    null,
    null,
    :'event1ID',
    :'eventTicketType1ID',
    '2099-01-04 00:00:00+00',
    'organizer_invitation',
    'declined',
    null,
    :'user4ID'
), (
    :'expiredInvitationOfferID',
    null,
    '2024-01-07 00:00:00+00',
    null,
    null,
    :'event1ID',
    :'eventTicketType1ID',
    '2024-01-08 00:00:00+00',
    'organizer_invitation',
    'expired',
    null,
    :'user5ID'
), (
    :'questionsInvitationOfferID',
    null,
    '2024-01-09 00:00:00+00',
    null,
    null,
    :'eventQuestionsID',
    :'eventQuestionsTicketTypeID',
    '2029-01-01 00:00:00+00',
    'organizer_invitation',
    'pending',
    null,
    :'user1ID'
);

-- Organizer invitation claimed into a pending external hold
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'externalOfferAdmissionOfferID',
    5000,
    '2024-01-11 00:00:00+00',
    'KRW',
    0,
    :'eventExternalID',
    :'eventExternalTicketTypeID',
    '2030-01-02 00:00:00+00',
    'organizer_invitation',
    'checkout_pending',
    'External admission',
    :'externalOfferUserID'
);

-- Declined organizer offer newer than the confirmed attendance
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
    :'rankingConfirmedOfferID',
    '2024-02-02 00:00:00+00',
    :'rankingConfirmedEventID',
    :'rankingConfirmedTicketTypeID',
    '2099-02-02 00:00:00+00',
    'organizer_invitation',
    'declined',
    :'rankingConfirmedUserID'
);

-- Expired organizer offer newer than the pending registration questions
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
    :'rankingQuestionsOfferID',
    '2024-02-02 00:00:00+00',
    :'rankingQuestionsEventID',
    :'rankingQuestionsTicketTypeID',
    '2024-02-03 00:00:00+00',
    'organizer_invitation',
    'expired',
    :'rankingQuestionsUserID'
);

-- Checkout question row created after its checkout-pending organizer offer,
-- inserted after offers because the offer trigger rejects active offers over attendance
insert into event_attendee (
    created_at,
    event_id,
    status,
    user_id
) values (
    '2024-01-05 00:00:00+00',
    :'event1ID',
    'registration-questions-pending',
    :'user3ID'
);

-- Completed discounted direct-charge purchase
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    status,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    :'eventPurchase1ID',
    2500,
    'direct-charge',
    'acct_attendee_search_test',
    'USD',
    500,
    'SAVE5',
    :'eventDiscountCode1ID',
    :'event1ID',
    :'eventTicketType1ID',
    0,
    'stripe',
    'ch_attendee_search_1',
    'cs_attendee_search_1',
    'acct_attendee_search_test',
    'pi_attendee_search_1',
    2500,
    '{}'::jsonb,
    'completed',
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'user1ID',
    '{}'::jsonb
);

-- Direct-charge purchase with a pending refund request
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    status,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    :'eventPurchase2ID',
    4000,
    'direct-charge',
    'acct_attendee_search_test',
    'USD',
    0,
    :'event2ID',
    :'eventTicketType2ID',
    0,
    'stripe',
    'ch_attendee_search_2',
    'cs_attendee_search_2',
    'acct_attendee_search_test',
    'pi_attendee_search_2',
    4000,
    '{}'::jsonb,
    'refund-requested',
    4000,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'VIP',
    :'user2ID',
    '{}'::jsonb
);

-- Pending direct-charge checkout
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    :'eventPurchasePendingCheckoutID',
    2500,
    'direct-charge',
    'acct_attendee_search_test',
    'USD',
    0,
    :'eventPendingCheckoutID',
    :'eventTicketTypePendingCheckoutID',
    current_timestamp + interval '10 minutes',
    'stripe',
    'acct_attendee_search_test',
    '{}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'pendingCheckoutUserID',
    '{}'::jsonb
);

-- Purchases representing abandoned checkout, active checkout, and worker-controlled progress
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot,

    final_platform_fee_amount_minor,
    hold_expires_at,
    provider_charge_id,
    provider_checkout_session_id,
    provider_payment_reference,
    provider_total_minor,
    refunded_at,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
select
    fixture.event_purchase_id,
    2500,
    'direct-charge',
    'acct_refund_progress_test',
    'USD',
    :'refundProgressEventID'::uuid,
    :'refundProgressTicketTypeID'::uuid,
    'stripe',
    'acct_refund_progress_test',
    '{}'::jsonb,
    fixture.status,
    'inclusive',
    'manual',
    'professional-event-admission',
    'Refund progress',
    fixture.user_id,
    '{}'::jsonb,

    case when fixture.status <> 'pending' then 0 end,
    fixture.hold_expires_at,
    case when fixture.status <> 'pending' then 'ch_' || fixture.event_purchase_id end,
    case when fixture.status <> 'pending' then 'cs_' || fixture.event_purchase_id end,
    fixture.provider_payment_reference,
    case when fixture.status <> 'pending' then 2500 end,
    fixture.refunded_at,
    case when fixture.status <> 'pending' then 2500 end,
    case when fixture.status <> 'pending' then 0 end
from (values
    (
        :'abandonedCheckoutPurchaseID'::uuid,
        'pending',
        :'abandonedCheckoutUserID'::uuid,
        current_timestamp - interval '10 minutes',
        null::text,
        null::timestamptz
    ),
    (
        :'progressAwaitingPurchaseID'::uuid,
        'pending',
        :'user1ID'::uuid,
        current_timestamp + interval '10 minutes',
        null::text,
        null::timestamptz
    ),
    (
        :'progressRecoveryPurchaseID'::uuid,
        'refund-pending',
        :'user2ID'::uuid,
        null::timestamptz,
        'pi_progress_2',
        null::timestamptz
    ),
    (
        :'progressRefundedPurchaseID'::uuid,
        'refunded',
        :'user3ID'::uuid,
        null::timestamptz,
        'pi_progress_3',
        current_timestamp
    ),
    (
        :'progressRetryPurchaseID'::uuid,
        'refund-pending',
        :'user6ID'::uuid,
        null::timestamptz,
        'pi_progress_6',
        null::timestamptz
    )
) as fixture(
    event_purchase_id,
    status,
    user_id,
    hold_expires_at,
    provider_payment_reference,
    refunded_at
);

-- Pending external hold shown as payment-pending
insert into event_purchase (
    amount_minor,
    charge_model,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    '2024-01-08 00:00:00+00',
    'KRW',
    :'eventExternalID',
    :'externalPendingPurchaseID',
    :'eventExternalTicketTypeID',
    '2030-01-02 00:00:00+00',
    0,
    0,
    'pending',
    'External admission',
    :'externalPendingUserID'
);

-- Completed external purchase exposing marked-by and reference fields
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    external_payment_details,
    external_payment_marked_by_user_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    '2024-01-10 12:00:00+00',
    'KRW',
    :'eventExternalID',
    :'externalCompletedPurchaseID',
    :'eventExternalTicketTypeID',
    'bank transfer received',
    :'externalMarkedByUserID',
    0,
    0,
    'completed',
    'External admission',
    :'externalCompletedUserID'
);

-- Pending external hold after re-registration without questionnaire answers
insert into event_purchase (
    amount_minor,
    charge_model,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    '2024-01-12 00:00:00+00',
    'KRW',
    :'eventExternalID',
    :'externalReregisterPurchaseID',
    :'eventExternalTicketTypeID',
    '2030-01-02 00:00:00+00',
    0,
    0,
    'pending',
    'External admission',
    :'externalReregisterUserID'
);

-- Pending external hold that must not duplicate the confirmed attendee
insert into event_purchase (
    amount_minor,
    charge_model,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    '2024-01-11 00:00:00+00',
    'KRW',
    :'eventExternalID',
    :'externalReplacementPurchaseID',
    :'eventExternalTicketTypeID',
    '2030-01-02 00:00:00+00',
    0,
    0,
    'pending',
    'External admission',
    :'externalReplacementUserID'
);

-- Pending external purchase for the claimed organizer invitation
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    charge_model,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    :'externalOfferAdmissionOfferID',
    5000,
    'external',
    '2024-01-11 00:00:00+00',
    'KRW',
    :'eventExternalID',
    :'externalOfferPurchaseID',
    :'eventExternalTicketTypeID',
    '2030-01-02 00:00:00+00',
    0,
    0,
    'pending',
    'External admission',
    :'externalOfferUserID'
);

-- Pending external hold that lapsed before being swept
insert into event_purchase (
    amount_minor,
    charge_model,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    '2024-02-01 00:00:00+00',
    'KRW',
    :'lapsedExternalHoldEventID',
    :'lapsedExternalHoldPurchaseID',
    :'lapsedExternalHoldTicketTypeID',
    current_timestamp - interval '10 minutes',
    0,
    0,
    'pending',
    'External admission',
    :'lapsedExternalHoldUserID'
);

-- Refund requests
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
)
values (
    :'eventRefundRequest2ID',
    :'eventPurchase2ID',
    :'user2ID',
    'pending'
);

-- Durable refund jobs behind the finalized, terminally failed, and exhausted refunds
insert into payment_job (
    attempt_count,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_job_id,
    payment_provider_id,
    status,

    claim_id,
    claimed_at,
    completed_at,
    failure_message,
    next_attempt_at
) values
    (0, :'progressRefundedPurchaseID', 'search-attendees-progress-refund-1-3a2e', 'event-purchase-refund', :'progressRefundedJobID', 'stripe', 'completed', null, null, current_timestamp, null, current_timestamp),
    (1, :'progressRecoveryPurchaseID', 'search-attendees-progress-refund-2-3a2e', 'event-purchase-refund', :'progressRecoveryJobID', 'stripe', 'failed', null, null, null, 'Provider refund terminal failure', now() + interval '100 years'),
    (10, :'progressRetryPurchaseID', 'search-attendees-progress-refund-4-3a2e', 'event-purchase-refund', :'progressRetryJobID', 'stripe', 'failed', null, null, null, 'Provider refund attempts exhausted', now() + interval '100 years');

-- Durable refunds exposing finalized, recovery-required, and exhausted refund progress
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status,
    terminal_failure,

    finalized_at,
    provider_refund_id,
    provider_refunded_at
) values
    (2500, 'USD', :'progressRefundedPurchaseID', :'progressRefundedRefundID', 'event-cancellation', :'progressRefundedJobID', 'stripe', 'finalized', false, current_timestamp, 're_progress_1', current_timestamp),
    (2500, 'USD', :'progressRecoveryPurchaseID', :'progressRecoveryRefundID', 'event-cancellation', :'progressRecoveryJobID', 'stripe', 'provider-failed', true, null, 're_progress_2', null),
    (2500, 'USD', :'progressRetryPurchaseID', :'progressRetryRefundID', 'event-cancellation', :'progressRetryJobID', 'stripe', 'provider-pending', false, null, null, null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should default to current enrollments for an active event
select results_eq(
    format($$
        with payload as (
            select search_event_attendees(
                %L::uuid,
                %L::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb as value
        )
        select
            value#>>'{attendees,0,user,user_id}',
            (value->>'total')::int
        from payload
    $$, :'groupID', :'attendanceFilterEventID'),
    format($$ values (%L::text, 1) $$, :'user1ID'),
    'Should default to current enrollments for an active event'
);

-- Should default to all enrollments for a canceled event
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'refundProgressEventID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb->>'total',
    '5',
    'Should default to all enrollments for a canceled event'
);

-- Should expose each attendee's refund progress
select is(
    (
        select jsonb_object_agg(
            attendee#>>'{user,user_id}',
            attendee->>'refund_progress'
        )
        from jsonb_array_elements(
            search_event_attendees(
                :'groupID'::uuid,
                :'refundProgressEventID'::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb->'attendees'
        ) attendee
    ),
    jsonb_build_object(
        :'abandonedCheckoutUserID', null,
        :'user1ID', 'awaiting-checkout',
        :'user2ID', 'recovery-required',
        :'user3ID', 'refunded',
        :'user6ID', 'retryable-failure'
    ),
    'Should expose each attendee''s refund progress'
);

-- Should expose refund payment job identifiers with refund progress
select is(
    (
        select jsonb_object_agg(
            attendee#>>'{user,user_id}',
            attendee->>'refund_payment_job_id'
        )
        from jsonb_array_elements(
            search_event_attendees(
                :'groupID'::uuid,
                :'refundProgressEventID'::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb->'attendees'
        ) attendee
        where attendee ? 'refund_progress'
    ),
    jsonb_build_object(
        :'user1ID', null,
        :'user2ID', :'progressRecoveryJobID',
        :'user3ID', :'progressRefundedJobID',
        :'user6ID', :'progressRetryJobID'
    ),
    'Should expose refund payment job identifiers with refund progress'
);

-- Should omit refund progress for an abandoned pending checkout
select ok(
    (
        select not (attendee ? 'refund_progress')
        from jsonb_array_elements(
            search_event_attendees(
                :'groupID'::uuid,
                :'refundProgressEventID'::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb->'attendees'
        ) attendee
        where attendee#>>'{user,user_id}' = :'abandonedCheckoutUserID'
    ),
    'Should omit refund progress for an abandoned pending checkout'
);

-- Should filter all enrollments
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'attendanceFilterEventID'::uuid,
        '{"limit": 50, "offset": 0, "status": "all"}'::jsonb
    )::jsonb->>'total',
    '2',
    'Should filter all enrollments'
);

-- Should filter current enrollments
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        '{"limit": 50, "offset": 0, "status": "current"}'::jsonb
    )::jsonb->>'total',
    '4',
    'Should filter current enrollments'
);

-- Should filter enrollment history
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        '{"limit": 50, "offset": 0, "status": "history"}'::jsonb
    )::jsonb->>'total',
    '2',
    'Should filter enrollment history'
);

-- Should filter every exact enrollment status
select results_eq(
    format($$
        with status_filters(status, event_id, user_id) as (
            values
                ('attendance-canceled', %L::uuid, %L::uuid),
                ('checkout-pending', %L::uuid, %L::uuid),
                ('confirmed', %L::uuid, %L::uuid),
                ('invitation-canceled', %L::uuid, %L::uuid),
                ('invitation-declined', %L::uuid, %L::uuid),
                ('invitation-expired', %L::uuid, %L::uuid),
                ('invitation-pending', %L::uuid, %L::uuid),
                ('registration-pending', %L::uuid, %L::uuid)
        )
        select
            sf.status,
            result.value#>>'{attendees,0,enrollment_status}',
            result.value#>>'{attendees,0,user,user_id}',
            (result.value->>'total')::int
        from status_filters sf
        cross join lateral (
            select search_event_attendees(
                %L::uuid,
                sf.event_id,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'status', sf.status
                )
            )::jsonb as value
        ) result
        order by sf.status
    $$,
        :'attendanceFilterEventID', :'user2ID',
        :'event1ID', :'user3ID',
        :'attendanceFilterEventID', :'user1ID',
        :'eventQuestionsID', :'user2ID',
        :'event1ID', :'user4ID',
        :'event1ID', :'user5ID',
        :'eventQuestionsID', :'user1ID',
        :'event1ID', :'user6ID',
        :'groupID'
    ),
    format($$
        values
            ('attendance-canceled'::text, 'attendance-canceled'::text, %L::text, 1),
            ('checkout-pending'::text, 'checkout-pending'::text, %L::text, 1),
            ('confirmed'::text, 'confirmed'::text, %L::text, 1),
            ('invitation-canceled'::text, 'invitation-canceled'::text, %L::text, 1),
            ('invitation-declined'::text, 'invitation-declined'::text, %L::text, 1),
            ('invitation-expired'::text, 'invitation-expired'::text, %L::text, 1),
            ('invitation-pending'::text, 'invitation-pending'::text, %L::text, 1),
            ('registration-pending'::text, 'registration-pending'::text, %L::text, 1)
    $$,
        :'user2ID',
        :'user3ID',
        :'user1ID',
        :'user2ID',
        :'user4ID',
        :'user5ID',
        :'user1ID',
        :'user6ID'
    ),
    'Should filter every exact enrollment status'
);

-- Should ignore an invalid enrollment status and use the event default
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'refundProgressEventID'::uuid,
        '{"limit": 50, "offset": 0, "status": "unknown"}'::jsonb
    )::jsonb->>'total',
    '5',
    'Should ignore an invalid enrollment status and use the event default'
);

-- Should return attendees for event1 with expected fields and order
select is(
    (
        select jsonb_set(
            result,
            '{attendees}',
            coalesce((
                select jsonb_agg(
                    attendee
                        - 'charge_model'
                        - 'completed_at'
                        - 'external_payment_deadline'
                        - 'external_payment_details'
                        - 'external_payment_marked_by'
                        - 'external_payment_reference'
                        - 'externally_paid'
                    order by ordinality
                )
                from jsonb_array_elements(result->'attendees')
                    with ordinality as t(attendee, ordinality)
            ), '[]'::jsonb)
        )
        from (
            select search_event_attendees(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0, 'status', 'all')
            )::jsonb as result
        ) s
    ),
    jsonb_build_object(
        'attendees', '[
            {"can_receive_attendee_email": true, "checked_in": true,  "created_at": 1704067200, "email": "alice-search-event-attendees@example.com", "manually_invited": true, "registration_answers": null, "enrollment_status": "confirmed", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000018", "username": "alice-search-event-attendees", "bio": "Maintains event infrastructure", "company": "Cloud Corp", "github_url": "https://github.com/alice", "name": "Alice", "photo_url": "https://example.com/alice.png", "provider": {"github": {"username": "alice-gh"}, "linuxfoundation": {"username": "alice-lf"}}, "title": "Principal Engineer", "website_url": "https://example.com/alice"}, "checked_in_at": 1704103200, "amount_minor": 2500, "currency_code": "USD", "discount_code": "SAVE5", "event_purchase_id": "3a2e0000-0000-0000-0000-000000000006", "refund_request_status": null, "ticket_title": "General admission", "admission_offer_id": null, "admission_offer_source": null, "admission_offer_status": null, "event_ticket_type_id": "3a2e0000-0000-0000-0000-000000000010", "offer_expires_at": null},
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "enrollment_status": "confirmed", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob-search-event-attendees", "photo_url": "https://example.com/bob.png"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null, "admission_offer_id": null, "admission_offer_source": null, "admission_offer_status": null, "event_ticket_type_id": null, "offer_expires_at": null},
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704585600, "email": "canceled@example.com", "manually_invited": true, "registration_answers": null, "enrollment_status": "invitation-expired", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000022", "username": "canceled", "name": "Canceled Invite"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": "General admission", "admission_offer_id": "3a2e0000-0000-0000-0000-000000000065", "admission_offer_source": "organizer_invitation", "admission_offer_status": "expired", "event_ticket_type_id": "3a2e0000-0000-0000-0000-000000000010", "offer_expires_at": 1704672000},
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704240000, "email": "pending@example.com", "manually_invited": true, "registration_answers": null, "enrollment_status": "checkout-pending", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000020", "username": "pending-search-event-attendees", "name": "Pending Invite"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": "General admission", "admission_offer_id": "3a2e0000-0000-0000-0000-000000000063", "admission_offer_source": "organizer_invitation", "admission_offer_status": "checkout_pending", "event_ticket_type_id": "3a2e0000-0000-0000-0000-000000000010", "offer_expires_at": 4071081600},
            {"can_receive_attendee_email": true, "checked_in": false, "created_at": 1704499200, "email": "questions-pending@example.com", "manually_invited": false, "registration_answers": null, "enrollment_status": "registration-pending", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000023", "username": "questions-pending-search-event-attendees", "name": "Questions Pending"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null, "admission_offer_id": null, "admission_offer_source": null, "admission_offer_status": null, "event_ticket_type_id": null, "offer_expires_at": null},
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704326400, "email": "rejected@example.com", "manually_invited": true, "registration_answers": null, "enrollment_status": "invitation-declined", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000021", "username": "rejected-search-event-attendees", "name": "Rejected Invite"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": "General admission", "admission_offer_id": "3a2e0000-0000-0000-0000-000000000064", "admission_offer_source": "organizer_invitation", "admission_offer_status": "declined", "event_ticket_type_id": "3a2e0000-0000-0000-0000-000000000010", "offer_expires_at": 4071168000}
        ]'::jsonb,
        'all_attendees_email_recipient_total', 2,
        'total', 6
    ),
    'Should return attendees for event1 with expected fields and order'
);

-- Should return paginated attendees when limit and offset are provided
select is(
    (
        select jsonb_set(
            result,
            '{attendees}',
            coalesce((
                select jsonb_agg(
                    attendee
                        - 'charge_model'
                        - 'completed_at'
                        - 'external_payment_deadline'
                        - 'external_payment_details'
                        - 'external_payment_marked_by'
                        - 'external_payment_reference'
                        - 'externally_paid'
                    order by ordinality
                )
                from jsonb_array_elements(result->'attendees')
                    with ordinality as t(attendee, ordinality)
            ), '[]'::jsonb)
        )
        from (
            select search_event_attendees(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object('limit', 1, 'offset', 1, 'status', 'all')
            )::jsonb as result
        ) s
    ),
    jsonb_build_object(
        'attendees', '[
            {"can_receive_attendee_email": false, "checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "enrollment_status": "confirmed", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob-search-event-attendees", "photo_url": "https://example.com/bob.png"}, "checked_in_at": null, "amount_minor": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "refund_request_status": null, "ticket_title": null, "admission_offer_id": null, "admission_offer_source": null, "admission_offer_status": null, "event_ticket_type_id": null, "offer_expires_at": null}
        ]'::jsonb,
        'all_attendees_email_recipient_total', 2,
        'total', 6
    ),
    'Should return paginated attendees when limit and offset are provided'
);

-- Should return full attendee list when pagination is omitted
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('status', 'all')
    )::jsonb,
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0, 'status', 'all')
    )::jsonb,
    'Should return full attendee list when pagination is omitted'
);

-- Should return attendees for event2
select is(
    (
        select jsonb_set(
            result,
            '{attendees}',
            coalesce((
                select jsonb_agg(
                    attendee
                        - 'charge_model'
                        - 'completed_at'
                        - 'external_payment_deadline'
                        - 'external_payment_details'
                        - 'external_payment_marked_by'
                        - 'external_payment_reference'
                        - 'externally_paid'
                    order by ordinality
                )
                from jsonb_array_elements(result->'attendees')
                    with ordinality as t(attendee, ordinality)
            ), '[]'::jsonb)
        )
        from (
            select search_event_attendees(
                :'groupID'::uuid,
                :'event2ID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0)
            )::jsonb as result
        ) s
    ),
    jsonb_build_object(
        'attendees', '[
            {"can_receive_attendee_email": false, "checked_in": true, "created_at": 1704240000, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "enrollment_status": "confirmed", "user": {"user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob-search-event-attendees", "photo_url": "https://example.com/bob.png"}, "checked_in_at": 1704294000, "amount_minor": 4000, "currency_code": "USD", "discount_code": null, "event_purchase_id": "3a2e0000-0000-0000-0000-000000000007", "refund_request_status": "pending", "ticket_title": "VIP", "admission_offer_id": null, "admission_offer_source": null, "admission_offer_status": null, "event_ticket_type_id": "3a2e0000-0000-0000-0000-000000000011", "offer_expires_at": null}
        ]'::jsonb,
        'all_attendees_email_recipient_total', 0,
        'total', 1
    ),
    'Should return attendees for event2'
);

-- Should return empty list when event scope is null
select is(
    search_event_attendees(
        :'groupID'::uuid,
        null::uuid,
        '{"limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'all_attendees_email_recipient_total', 0,
        'attendees', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event scope is null'
);

-- Should return empty list for non-existing event
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'missingEventID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'all_attendees_email_recipient_total', 0,
        'attendees', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- Should return empty list when event belongs to another group
select is(
    search_event_attendees(
        :'group2ID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'all_attendees_email_recipient_total', 0,
        'attendees', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event belongs to another group'
);

-- Should filter attendees by identity search query without changing all-recipient count
select is(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'ali'
                )
            )::jsonb as data
        )
        select jsonb_build_object(
            'all_attendees_email_recipient_total', data->'all_attendees_email_recipient_total',
            'first', data#>'{attendees,0,user,user_id}',
            'total', data->'total'
        )
        from result
    ),
    jsonb_build_object(
        'all_attendees_email_recipient_total', 2,
        'first', :'user1ID'::uuid,
        'total', 1
    ),
    'Should filter attendees by identity search query without changing all-recipient count'
);

-- Should filter attendees whose names look like stop words
select is(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'eventStopwordSearchID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'may'
                )
            )::jsonb as data
        )
        select jsonb_build_object(
            'all_attendees_email_recipient_total', data->'all_attendees_email_recipient_total',
            'first', data#>'{attendees,0,user,user_id}',
            'total', data->'total'
        )
        from result
    ),
    jsonb_build_object(
        'all_attendees_email_recipient_total', 1,
        'first', :'userStopwordSearchID'::uuid,
        'total', 1
    ),
    'Should filter attendees whose names look like stop words'
);

-- Should filter attendees by company search query
select is(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'cloud corp'
                )
            )::jsonb as data
        )
        select jsonb_build_object(
            'all_attendees_email_recipient_total', data->'all_attendees_email_recipient_total',
            'first', data#>'{attendees,0,user,user_id}',
            'total', data->'total'
        )
        from result
    ),
    jsonb_build_object(
        'all_attendees_email_recipient_total', 2,
        'first', :'user1ID'::uuid,
        'total', 1
    ),
    'Should filter attendees by company search query'
);

-- Should filter attendees by title search query
select is(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'principal engineer'
                )
            )::jsonb as data
        )
        select jsonb_build_object(
            'all_attendees_email_recipient_total', data->'all_attendees_email_recipient_total',
            'first', data#>'{attendees,0,user,user_id}',
            'total', data->'total'
        )
        from result
    ),
    jsonb_build_object(
        'all_attendees_email_recipient_total', 2,
        'first', :'user1ID'::uuid,
        'total', 1
    ),
    'Should filter attendees by title search query'
);

-- Should sort attendees by RSVP date descending
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'sort', 'created-at-desc',
            'status', 'all'
        )
    )::jsonb#>>'{attendees,0,user,username}',
    'canceled',
    'Should sort attendees by created_at descending'
);

-- Should filter attendees with a user title
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'status', 'all',
            'title', 'present'
        )
    )::jsonb->>'total',
    '1',
    'Should filter attendees with a title'
);

-- Should filter attendees without a user title
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'status', 'all',
            'title', 'missing'
        )
    )::jsonb->>'total',
    '5',
    'Should filter attendees without a title'
);

-- Should filter attendees by checked_in status
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'checked_in', true,
            'limit', 50,
            'offset', 0,
            'status', 'all'
        )
    )::jsonb->>'total',
    '1',
    'Should filter attendees by checked_in status'
);

-- Should filter unchecked attendees without returning non-attendee rows
select results_eq(
    format($$
        with payload as (
            select search_event_attendees(
                %L::uuid,
                %L::uuid,
                '{"checked_in": false, "limit": 50, "offset": 0, "status": "all"}'::jsonb
            )::jsonb as value
        )
        select
            value#>>'{attendees,0,user,user_id}',
            (value->>'total')::int
        from payload
    $$, :'groupID', :'event1ID'),
    format($$ values (%L::text, 1) $$, :'user2ID'),
    'Should filter unchecked attendees without returning non-attendee rows'
);

-- Should filter attendees by event ticket type identifiers
select is(
    search_event_attendees(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'event_ticket_type_ids', jsonb_build_array(:'eventTicketType1ID'::uuid),
            'limit', 50,
            'offset', 0,
            'status', 'all'
        )
    )::jsonb->>'total',
    '4',
    'Should filter attendees by event ticket type identifiers'
);

-- Should exclude active pending checkout holds from email recipient eligibility
select ok(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'eventPendingCheckoutID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and (data->>'all_attendees_email_recipient_total')::int = 0
        and (data#>>'{attendees,0,can_receive_attendee_email}')::boolean = false
        from result
    ),
    'Should exclude active pending checkout holds from email recipient eligibility'
);

-- Should exclude lapsed external holds without attendance from email recipients
select is(
    (
        select jsonb_build_object(
            'can_receive_attendee_email', (data#>>'{attendees,0,can_receive_attendee_email}')::boolean,
            'enrollment_status', data#>>'{attendees,0,enrollment_status}',
            'recipient_total', (data->>'all_attendees_email_recipient_total')::int,
            'total', (data->>'total')::int
        )
        from (
            select search_event_attendees(
                :'groupID'::uuid,
                :'lapsedExternalHoldEventID'::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb as data
        ) result
    ),
    jsonb_build_object(
        'can_receive_attendee_email', false,
        'enrollment_status', 'checkout-pending',
        'recipient_total', 0,
        'total', 1
    ),
    'Should exclude lapsed external holds without attendance from email recipients'
);

-- Should apply organizer opt-outs and owner group mutes to attendee email eligibility
select is(
    (
        select jsonb_build_object(
            'recipient_total', (data->>'all_attendees_email_recipient_total')::int,
            'recipients', (
                select jsonb_object_agg(
                    attendee#>>'{user,user_id}',
                    (attendee->>'can_receive_attendee_email')::boolean
                )
                from jsonb_array_elements(data->'attendees') attendee
            )
        )
        from (
            select search_event_attendees(
                :'groupID'::uuid,
                :'focusedEventID'::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb as data
        ) result
    ),
    jsonb_build_object(
        'recipient_total', 2,
        'recipients', jsonb_build_object(
            :'focusedEligibleUserID', true,
            :'focusedOwnerMutedUserID', false,
            :'focusedUnrelatedMutedUserID', true
        )
    ),
    'Should apply organizer opt-outs and owner group mutes to attendee email eligibility'
);

-- Should include registration answers in attendee search results
select is(
    (
        select attendee->'registration_answers'
        from jsonb_array_elements(
            search_event_attendees(:'groupID'::uuid, :'eventQuestionsID'::uuid, jsonb_build_object('limit', 10, 'offset', 0))::jsonb->'attendees'
        ) attendee
        where attendee#>>'{user,user_id}' = :'questionsAttendeeUserID'
    ),
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', :'registrationQuestionID',
            'value', 'Attendee answer'
        ))
    ),
    'Should include registration answers in attendee search results'
);

-- Pending organizer offers are not attendees eligible for custom notifications.
select ok(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'eventQuestionsID'::uuid,
                jsonb_build_object('limit', 10, 'offset', 0)
            )::jsonb as data
        )
        select (data->>'all_attendees_email_recipient_total')::int = 0
        and (
            select (attendee->>'can_receive_attendee_email')::boolean
            from jsonb_array_elements(data->'attendees') attendee
            where attendee#>>'{user,user_id}' = :'user1ID'
        ) = false
        from result
    ),
    'Should exclude pending organizer offers from attendee email eligibility'
);

-- Should expose payment-pending status and external purchase fields
select is(
    (
        select attendee
        from jsonb_array_elements(
            search_event_attendees(
                :'groupID'::uuid,
                :'eventExternalID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0, 'status', 'payment-pending')
            )::jsonb->'attendees'
        ) attendee
        where (attendee#>>'{user,user_id}')::uuid = :'externalPendingUserID'::uuid
    ),
    jsonb_build_object(
        'can_receive_attendee_email', false,
        'checked_in', false,
        'created_at', 1704672000,
        'email', 'external-pending@example.com',
        'enrollment_status', 'payment-pending',
        'manually_invited', false,
        'registration_answers', null,
        'user', jsonb_build_object(
            'user_id', :'externalPendingUserID'::uuid,
            'username', 'external-pending'
        ),
        'admission_offer_id', null,
        'admission_offer_source', null,
        'admission_offer_status', null,
        'amount_minor', 5000,
        'charge_model', 'external',
        'checked_in_at', null,
        'completed_at', null,
        'currency_code', 'KRW',
        'discount_code', null,
        'event_purchase_id', :'externalPendingPurchaseID'::uuid,
        'event_ticket_type_id', :'eventExternalTicketTypeID'::uuid,
        'external_payment_deadline', 1893542400,
        'external_payment_details', null,
        'external_payment_marked_by', null,
        'external_payment_reference', :'externalPendingPurchaseID'::uuid,
        'externally_paid', false,
        'offer_expires_at', null,
        'refund_request_status', null,
        'ticket_title', 'External admission'
    ),
    'Should expose payment-pending status and external purchase fields'
);

-- Should expose completed external payment metadata for organizers
select is(
    (
        select attendee
        from jsonb_array_elements(
            search_event_attendees(
                :'groupID'::uuid,
                :'eventExternalID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0, 'status', 'confirmed')
            )::jsonb->'attendees'
        ) attendee
        where (attendee#>>'{user,user_id}')::uuid = :'externalCompletedUserID'::uuid
    ),
    jsonb_build_object(
        'can_receive_attendee_email', true,
        'checked_in', false,
        'created_at', 1704758400,
        'email', 'external-completed@example.com',
        'enrollment_status', 'confirmed',
        'manually_invited', false,
        'registration_answers', null,
        'user', jsonb_build_object(
            'user_id', :'externalCompletedUserID'::uuid,
            'username', 'external-completed'
        ),
        'admission_offer_id', null,
        'admission_offer_source', null,
        'admission_offer_status', null,
        'amount_minor', 5000,
        'charge_model', 'external',
        'checked_in_at', null,
        'completed_at', 1704888000,
        'currency_code', 'KRW',
        'discount_code', null,
        'event_purchase_id', :'externalCompletedPurchaseID'::uuid,
        'event_ticket_type_id', :'eventExternalTicketTypeID'::uuid,
        'external_payment_deadline', null,
        'external_payment_details', 'bank transfer received',
        'external_payment_marked_by', 'external-marked-by',
        'external_payment_reference', :'externalCompletedPurchaseID'::uuid,
        'externally_paid', true,
        'offer_expires_at', null,
        'refund_request_status', null,
        'ticket_title', 'External admission'
    ),
    'Should expose completed external payment metadata for organizers'
);

-- Should expose claimed organizer invitations holding a pending external purchase
select ok(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'eventExternalID'::uuid,
                '{}'::jsonb
            )::jsonb as data
        )
        select (attendee->>'enrollment_status') = 'payment-pending'
        and (attendee->>'event_purchase_id') = :'externalOfferPurchaseID'
        and (attendee->>'external_payment_reference') = :'externalOfferPurchaseID'
        from result
        cross join lateral jsonb_array_elements(data->'attendees') attendee
        where (attendee#>>'{user,user_id}')::uuid = :'externalOfferUserID'::uuid
    ),
    'Should expose claimed organizer invitations holding a pending external purchase'
);

-- Should expose payment-pending after re-registering over an attendance-canceled row
select ok(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'eventExternalID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0, 'status', 'payment-pending')
            )::jsonb as data
        )
        select (attendee->>'enrollment_status') = 'payment-pending'
        and (attendee->>'event_purchase_id') = :'externalReregisterPurchaseID'
        from result
        cross join lateral jsonb_array_elements(data->'attendees') attendee
        where (attendee#>>'{user,user_id}')::uuid = :'externalReregisterUserID'::uuid
    ),
    'Should expose payment-pending after re-registering over an attendance-canceled row'
);

-- Should keep a confirmed attendee ahead of a replacement external hold
select ok(
    (
        with result as (
            select search_event_attendees(
                :'groupID'::uuid,
                :'eventExternalID'::uuid,
                '{}'::jsonb
            )::jsonb as data
        )
        select count(*) filter (
            where (attendee#>>'{user,user_id}')::uuid = :'externalReplacementUserID'::uuid
        ) = 1
        and bool_and(attendee->>'enrollment_status' = 'confirmed')
            filter (
                where (attendee#>>'{user,user_id}')::uuid = :'externalReplacementUserID'::uuid
            )
        from result
        cross join lateral jsonb_array_elements(data->'attendees') attendee
    ),
    'Should keep a confirmed attendee ahead of a replacement external hold'
);

-- Should keep active attendance ahead of a newer declined organizer offer
select is(
    (
        select jsonb_build_object(
            'admission_offer_id', data#>>'{attendees,0,admission_offer_id}',
            'can_receive_attendee_email', (data#>>'{attendees,0,can_receive_attendee_email}')::boolean,
            'enrollment_status', data#>>'{attendees,0,enrollment_status}',
            'recipient_total', (data->>'all_attendees_email_recipient_total')::int,
            'total', (data->>'total')::int,
            'user_id', data#>>'{attendees,0,user,user_id}'
        )
        from (
            select search_event_attendees(
                :'groupID'::uuid,
                :'rankingConfirmedEventID'::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb as data
        ) result
    ),
    jsonb_build_object(
        'admission_offer_id', null,
        'can_receive_attendee_email', true,
        'enrollment_status', 'confirmed',
        'recipient_total', 1,
        'total', 1,
        'user_id', :'rankingConfirmedUserID'
    ),
    'Should keep active attendance ahead of a newer declined organizer offer'
);

-- Should list active attendance with a newer declined organizer offer as checked in
select is(
    (
        select jsonb_build_object(
            'checked_in', (data#>>'{attendees,0,checked_in}')::boolean,
            'enrollment_status', data#>>'{attendees,0,enrollment_status}',
            'total', (data->>'total')::int,
            'user_id', data#>>'{attendees,0,user,user_id}'
        )
        from (
            select search_event_attendees(
                :'groupID'::uuid,
                :'rankingConfirmedEventID'::uuid,
                '{"checked_in": true, "limit": 50, "offset": 0}'::jsonb
            )::jsonb as data
        ) result
    ),
    jsonb_build_object(
        'checked_in', true,
        'enrollment_status', 'confirmed',
        'total', 1,
        'user_id', :'rankingConfirmedUserID'
    ),
    'Should list active attendance with a newer declined organizer offer as checked in'
);

-- Should keep pending registration questions ahead of a newer expired organizer offer
select is(
    (
        select jsonb_build_object(
            'admission_offer_id', data#>>'{attendees,0,admission_offer_id}',
            'enrollment_status', data#>>'{attendees,0,enrollment_status}',
            'total', (data->>'total')::int
        )
        from (
            select search_event_attendees(
                :'groupID'::uuid,
                :'rankingQuestionsEventID'::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb as data
        ) result
    ),
    jsonb_build_object(
        'admission_offer_id', null,
        'enrollment_status', 'registration-pending',
        'total', 1
    ),
    'Should keep pending registration questions ahead of a newer expired organizer offer'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
