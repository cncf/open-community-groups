-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventApprovalID '00000000-0000-0000-0000-000000000044'
\set eventCanceledID '00000000-0000-0000-0000-000000000042'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventID '00000000-0000-0000-0000-000000000041'
\set eventPurchaseID '00000000-0000-0000-0000-000000000061'
\set eventPurchaseCurrentID '00000000-0000-0000-0000-000000000062'
\set eventPurchaseProcessingID '00000000-0000-0000-0000-000000000063'
\set eventRefundRequestID '00000000-0000-0000-0000-000000000071'
\set eventRefundRequestProcessingID '00000000-0000-0000-0000-000000000072'
\set eventStartedNoEndID '00000000-0000-0000-0000-000000000043'
\set groupID '00000000-0000-0000-0000-000000000031'
\set user1ID '00000000-0000-0000-0000-000000000051'
\set user2ID '00000000-0000-0000-0000-000000000052'
\set user4ID '00000000-0000-0000-0000-000000000054'
\set user5ID '00000000-0000-0000-0000-000000000055'
\set user6ID '00000000-0000-0000-0000-000000000056'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'communityID', 'cncf-sea', 'CNCF Seattle', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'community2ID', 'cncf-ny', 'CNCF NY', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'Tech', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, logo_url, active)
values (:'groupID', 'Test Group', 'test-group', :'communityID', :'categoryID', 'https://example.com/group.png', true);

-- User
insert into "user" (user_id, auth_hash, email, username, name)
values
    (:'user1ID', 'h1', 'att1@example.com', 'att1', 'Att One'),
    (:'user2ID', 'h2', 'att2@example.com', 'att2', 'Att Two'),
    ('00000000-0000-0000-0000-000000000053', 'h3', 'att3@example.com', 'att3', 'Att Three'),
    (:'user4ID', 'h4', 'att4@example.com', 'att4', 'Att Four'),
    (:'user5ID', 'h5', 'att5@example.com', 'att5', 'Att Five'),
    (:'user6ID', 'h6', 'att6@example.com', 'att6', 'Att Six');

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

-- Event ticket type
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values
    ('00000000-0000-0000-0000-000000000081'::uuid, true, :'eventID', 1, 100, 'General admission'),
    ('00000000-0000-0000-0000-000000000082'::uuid, true, :'eventID', 2, 100, 'VIP');

-- Event Attendee - user1 is checked in
insert into event_attendee (event_id, user_id, checked_in, checked_in_at) values (:'eventID', :'user1ID', true, current_timestamp);

-- Event Attendee - user2 is not checked in
insert into event_attendee (event_id, user_id, checked_in) values (:'eventID', :'user2ID', false);

-- Event Attendee - started event without end should still report attendee
insert into event_attendee (event_id, user_id, checked_in)
values (:'eventStartedNoEndID', :'user1ID', false);

-- Event Waitlist
insert into event_waitlist (event_id, user_id)
values
    (:'eventID', '00000000-0000-0000-0000-000000000053'),
    (:'eventCanceledID', '00000000-0000-0000-0000-000000000053');

-- Event invitation requests
insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by)
values
    (:'eventApprovalID', :'user5ID', 'pending', null, null),
    (:'eventApprovalID', :'user6ID', 'rejected', current_timestamp, :'user1ID'),
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
    '00000000-0000-0000-0000-000000000081',
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
    '00000000-0000-0000-0000-000000000082',
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
    '00000000-0000-0000-0000-000000000082',
    null,
    'refund-requested',
    'VIP',
    :'user2ID'
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
        '00000000-0000-0000-0000-000000000053'::uuid
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

-- Should return none for waitlisted users on canceled events
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventCanceledID'::uuid,
        '00000000-0000-0000-0000-000000000053'::uuid
    )::jsonb,
    '{
        "is_checked_in": false,
        "purchase_amount_minor": null,
        "refund_request_status": null,
        "resume_checkout_url": null,
        "status": "none"
    }'::jsonb,
    'Should return none for waitlisted users on canceled events'
);

-- Should return none for non-attendee
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventID'::uuid,
        '00000000-0000-0000-0000-000000000057'::uuid
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
