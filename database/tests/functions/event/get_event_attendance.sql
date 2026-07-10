-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(20);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '5e050000-0000-0000-0000-000000000001'
\set communityID '5e050000-0000-0000-0000-000000000002'
\set eventApprovalID '5e050000-0000-0000-0000-000000000003'
\set eventCanceledID '5e050000-0000-0000-0000-000000000004'
\set eventCategoryID '5e050000-0000-0000-0000-000000000005'
\set eventDraftCanceledID '5e050000-0000-0000-0000-000000000006'
\set eventID '5e050000-0000-0000-0000-000000000007'
\set eventPurchaseCurrentID '5e050000-0000-0000-0000-000000000008'
\set eventPurchaseID '5e050000-0000-0000-0000-000000000009'
\set eventPurchaseProcessingID '5e050000-0000-0000-0000-00000000000a'
\set eventPurchaseQuestionsExpiredID '5e050000-0000-0000-0000-00000000000b'
\set eventPurchaseQuestionsPendingID '5e050000-0000-0000-0000-00000000000c'
\set eventQuestionsID '5e050000-0000-0000-0000-00000000000d'
\set eventRefundRequestID '5e050000-0000-0000-0000-00000000000e'
\set eventRefundRequestProcessingID '5e050000-0000-0000-0000-00000000000f'
\set eventStartedNoEndID '5e050000-0000-0000-0000-000000000010'
\set groupCategoryID '5e050000-0000-0000-0000-000000000011'
\set groupID '5e050000-0000-0000-0000-000000000012'
\set nonAttendeeUserID '5e050000-0000-0000-0000-000000000013'
\set questionID '5e050000-0000-0000-0000-000000000014'
\set questionsCheckoutExpiredUserID '5e050000-0000-0000-0000-000000000015'
\set questionsCheckoutUserID '5e050000-0000-0000-0000-000000000016'
\set questionsInvitedUserID '5e050000-0000-0000-0000-000000000017'
\set questionsTicketTypeID '5e050000-0000-0000-0000-000000000018'
\set ticketTypeGeneralID '5e050000-0000-0000-0000-000000000019'
\set ticketTypeVIPID '5e050000-0000-0000-0000-00000000001a'
\set user1ID '5e050000-0000-0000-0000-00000000001b'
\set user2ID '5e050000-0000-0000-0000-00000000001c'
\set user3ID '5e050000-0000-0000-0000-00000000001d'
\set user4ID '5e050000-0000-0000-0000-00000000001e'
\set user5ID '5e050000-0000-0000-0000-00000000001f'
\set user6ID '5e050000-0000-0000-0000-000000000020'
\set user7ID '5e050000-0000-0000-0000-000000000021'
\set user8ID '5e050000-0000-0000-0000-000000000022'
\set user9ID '5e050000-0000-0000-0000-000000000023'

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
    'cncf-sea',
    'CNCF Seattle',
    'Seattle cloud native community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'community2ID',
    'cncf-ny',
    'CNCF NY',
    'New York cloud native community',
    'https://example.com/ny-banner-mobile.png',
    'https://example.com/ny-banner.png',
    'https://example.com/ny-logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Tech');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    logo_url
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    true,
    'https://example.com/group.png'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'user1ID', 'h1', 'att1@example.com', true, 'att1', 'Att One'
), (
    :'user2ID', 'h2', 'att2@example.com', true, 'att2', 'Att Two'
), (
    :'user3ID', 'h3', 'att3@example.com', true, 'att3', 'Att Three'
), (
    :'user4ID', 'h4', 'att4@example.com', true, 'att4', 'Att Four'
), (
    :'user5ID', 'h5', 'att5@example.com', true, 'att5', 'Att Five'
), (
    :'user6ID', 'h6', 'att6@example.com', true, 'att6', 'Att Six'
), (
    :'user7ID', 'h7', 'att7@example.com', true, 'att7', 'Att Seven'
), (
    :'user8ID', 'h8', 'att8@example.com', true, 'att8', 'Att Eight'
), (
    :'user9ID', 'h12', 'att9@example.com', true, 'att9', 'Att Nine'
), (
    :'questionsCheckoutUserID', 'h9', 'rq-checkout@test.com', true, 'rq-checkout', null
), (
    :'questionsCheckoutExpiredUserID',
    'h10',
    'rq-expired-checkout@test.com',
    true,
    'rq-expired-checkout',
    null
), (
    :'questionsInvitedUserID', 'h11', 'rq-invited@test.com', true, 'rq-invited', null
);

-- Event
insert into event (
    event_id,
    attendee_approval_required,
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
    starts_at
) values (
    :'eventID',
    false,
    'Event',
    'event',
    'desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    null
), (
    :'eventApprovalID',
    true,
    'Approval Event',
    'approval-event',
    'desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    null,
    true,
    false,
    null
), (
    :'eventCanceledID',
    false,
    'Canceled Event',
    'canceled-event',
    'desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    null,
    true,
    true,
    null
), (
    :'eventDraftCanceledID',
    false,
    'Canceled Draft Event',
    'canceled-draft-event',
    'desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    null,
    false,
    true,
    null
), (
    :'eventStartedNoEndID',
    false,
    'Started Event Without End',
    'started-event-without-end',
    'desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    null,
    true,
    false,
    current_timestamp - interval '1 hour'
);

-- Event requiring invited users to answer registration questions
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
    starts_at,
    registration_questions
) values (
    :'eventQuestionsID',
    'Questions Event',
    'questions-event',
    'd',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    '2030-01-01 10:00:00+00',
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb
);

-- Event ticket type
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values
    (:'ticketTypeGeneralID', true, :'eventID', 1, 100, 'General admission'),
    (:'ticketTypeVIPID', true, :'eventID', 2, 100, 'VIP'),
    (:'questionsTicketTypeID', true, :'eventQuestionsID', 1, 100, 'Questions general admission');

-- Event Attendee - user1 is checked in
insert into event_attendee (
    event_id,
    user_id,
    checked_in,
    checked_in_at
) values (
    :'eventID',
    :'user1ID',
    true,
    current_timestamp
);

-- Event Attendee - user2 is not checked in
insert into event_attendee (event_id, user_id, checked_in) values (:'eventID', :'user2ID', false);

-- Event Attendee - started event without end should still report attendee
insert into event_attendee (event_id, user_id, checked_in)
values (:'eventStartedNoEndID', :'user1ID', false);

-- Event Attendee - canceled event should still report attendee
insert into event_attendee (event_id, user_id, checked_in)
values (:'eventCanceledID', :'user1ID', false);

-- Event Attendee - canceled draft event should not report attendee
insert into event_attendee (event_id, user_id, checked_in)
values (:'eventDraftCanceledID', :'user2ID', false);

-- Event Attendee - pending organizer invitation should report approved invitation
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'eventID', :'user8ID', true, 'invitation-pending');

-- Event Attendee - pending non-manual invitation should not report attendee
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'user9ID', 'invitation-pending');

-- Event Attendee - pending registration questions should report pending state
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'eventQuestionsID', :'questionsInvitedUserID', true, 'registration-questions-pending'),
    (:'eventQuestionsID', :'questionsCheckoutUserID', false, 'registration-questions-pending'),
    (
        :'eventQuestionsID',
        :'questionsCheckoutExpiredUserID',
        false,
        'registration-questions-pending'
    );

-- Event Waitlist
insert into event_waitlist (event_id, user_id)
values
    (:'eventID', :'user3ID'),
    (:'eventCanceledID', :'user3ID');

-- Event invitation requests
insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by)
values
    (:'eventApprovalID', :'user5ID', 'pending', null, null),
    (:'eventApprovalID', :'user6ID', 'rejected', current_timestamp, :'user1ID'),
    (:'eventApprovalID', :'user7ID', 'accepted', current_timestamp, :'user1ID'),
    (:'eventID', :'user6ID', 'rejected', current_timestamp, :'user1ID');

-- Event purchase
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    refunded_at,
    status,
    ticket_title,
    user_id
) values (
    :'eventPurchaseID',
    2500,
    '2030-01-01 00:00:00+00',
    'USD',
    :'eventID',
    :'ticketTypeGeneralID',
    '2030-01-02 00:00:00+00',
    'refunded',
    'General admission',
    :'user4ID'
), (
    :'eventPurchaseCurrentID',
    3000,
    '2030-01-03 00:00:00+00',
    'USD',
    :'eventID',
    :'ticketTypeVIPID',
    null,
    'completed',
    'VIP',
    :'user4ID'
), (
    :'eventPurchaseProcessingID',
    3500,
    '2030-01-04 00:00:00+00',
    'USD',
    :'eventID',
    :'ticketTypeVIPID',
    null,
    'refund-requested',
    'VIP',
    :'user2ID'
);

-- Completed purchase used to expose paid attendance details
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    provider_checkout_url,
    status,
    ticket_title,
    user_id
) values (
    :'eventPurchaseQuestionsPendingID',
    1200,
    'USD',
    :'eventQuestionsID',
    :'questionsTicketTypeID',
    current_timestamp + interval '10 minutes',
    'https://example.test/checkout/resume',
    'pending',
    'Questions general admission',
    :'questionsCheckoutUserID'
), (
    :'eventPurchaseQuestionsExpiredID',
    1200,
    'USD',
    :'eventQuestionsID',
    :'questionsTicketTypeID',
    current_timestamp - interval '10 minutes',
    'https://example.test/checkout/expired',
    'pending',
    'Questions general admission',
    :'questionsCheckoutExpiredUserID'
);

-- Event refund request
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'eventRefundRequestID',
    :'eventPurchaseID',
    :'user4ID',
    'approved'
), (
    :'eventRefundRequestProcessingID',
    :'eventPurchaseProcessingID',
    :'user2ID',
    'approving'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return attendee status for checked-in attendee
select is(
    get_event_attendance(:'communityID'::uuid, :'eventID'::uuid, :'user1ID'::uuid)::jsonb,
    '{
        "is_checked_in": true,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "attendee"
    }'::jsonb,
    'Should return attendee status for a checked-in attendee'
);

-- Should return attendee status for attendee not checked in
select is(
    get_event_attendance(:'communityID'::uuid, :'eventID'::uuid, :'user2ID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": 3500,
        "refund_request_status": "approving",
        "resume_checkout_url": null,
        "status": "attendee"
    }'::jsonb,
    'Should return attendee purchase and refund processing state when a refund is being approved'
);

-- Should return attendee status for a started event without an end time
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventStartedNoEndID'::uuid,
        :'user1ID'::uuid
    )::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "attendee"
    }'::jsonb,
    'Should return attendee status for a started event without an end time'
);

-- Should return none when scoped by wrong community
select is(
    get_event_attendance(:'community2ID'::uuid, :'eventID'::uuid, :'user1ID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "none"
    }'::jsonb,
    'Should return none when scoped by wrong community'
);

-- Should keep purchase and refund request scoped to the validated community
select is(
    get_event_attendance(:'community2ID'::uuid, :'eventID'::uuid, :'user4ID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "none"
    }'::jsonb,
    'Should not expose purchase or refund request details outside the validated community scope'
);

-- Should only return refund state for the selected current purchase
select is(
    get_event_attendance(:'communityID'::uuid, :'eventID'::uuid, :'user4ID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": 3000,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "none"
    }'::jsonb,
    'Should not attach an older refund request to the current purchase state'
);

-- Should return waitlisted status for waitlisted user
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventID'::uuid,
        :'user3ID'::uuid
    )::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "waitlisted"
    }'::jsonb,
    'Should return waitlisted status for a waitlisted user'
);

-- Should return invitation approved for pending organizer-created invitations
select is(
    get_event_attendance(:'communityID'::uuid, :'eventID'::uuid, :'user8ID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "manually_invited": true,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "invitation-approved"
    }'::jsonb,
    'Should return invitation approved for pending organizer-created invitations'
);

-- Should return none for pending non-manual invitations
select is(
    get_event_attendance(:'communityID'::uuid, :'eventID'::uuid, :'user9ID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "none"
    }'::jsonb,
    'Should return none for pending non-manual invitations'
);

-- Should return pending approval status for pending invitation request
select is(
    get_event_attendance(:'communityID'::uuid, :'eventApprovalID'::uuid, :'user5ID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "pending-approval"
    }'::jsonb,
    'Should return pending approval status for pending invitation request'
);

-- Should return invitation approved status for accepted invitation request
select is(
    get_event_attendance(:'communityID'::uuid, :'eventApprovalID'::uuid, :'user7ID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "invitation-approved"
    }'::jsonb,
    'Should return invitation approved status for accepted invitation request'
);

-- Should return rejected status for rejected invitation request
select is(
    get_event_attendance(:'communityID'::uuid, :'eventApprovalID'::uuid, :'user6ID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "rejected"
    }'::jsonb,
    'Should return rejected status for rejected invitation request'
);

-- Should ignore rejected invitation requests when approval is disabled
select is(
    get_event_attendance(:'communityID'::uuid, :'eventID'::uuid, :'user6ID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "none"
    }'::jsonb,
    'Should ignore rejected invitation requests when approval is disabled'
);

-- Should return attendee status for attendees on canceled events
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventCanceledID'::uuid,
        :'user1ID'::uuid
    )::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "attendee"
    }'::jsonb,
    'Should return attendee status for attendees on canceled events'
);

-- Should return waitlisted status for waitlisted users on canceled events
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventCanceledID'::uuid,
        :'user3ID'::uuid
    )::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "waitlisted"
    }'::jsonb,
    'Should return waitlisted status for waitlisted users on canceled events'
);

-- Should return none for attendees on canceled draft events
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventDraftCanceledID'::uuid,
        :'user2ID'::uuid
    )::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "none"
    }'::jsonb,
    'Should return none for attendees on canceled draft events'
);

-- Should return none for non-attendee
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventID'::uuid,
        :'nonAttendeeUserID'::uuid
    )::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "none"
    }'::jsonb,
    'Should return none for a non-attendee'
);

-- Should report pending registration questions in event attendance state
select is(
    get_event_attendance(:'communityID'::uuid, :'eventQuestionsID'::uuid, :'questionsInvitedUserID'::uuid)::jsonb->>'status',
    'registration-questions-pending',
    'Should report pending registration questions in event attendance state'
);

-- Should report pending payment before pending registration questions
select is(
    get_event_attendance(:'communityID'::uuid, :'eventQuestionsID'::uuid, :'questionsCheckoutUserID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": 1200,
        "refund_request_status": null,
        "resume_checkout_url": "https://example.test/checkout/resume",
        "status": "pending-payment"
    }'::jsonb,
    'Should report active pending checkout before pending registration questions'
);

-- Should ignore expired pending payments before pending registration questions
select is(
    get_event_attendance(:'communityID'::uuid, :'eventQuestionsID'::uuid, :'questionsCheckoutExpiredUserID'::uuid)::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "registration-questions-pending"
    }'::jsonb,
    'Should ignore expired pending checkout before pending registration questions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
