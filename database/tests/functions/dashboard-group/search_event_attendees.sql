-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventDiscountCode1ID '00000000-0000-0000-0000-000000000061'
\set eventPurchase1ID '00000000-0000-0000-0000-000000000071'
\set eventPurchase2ID '00000000-0000-0000-0000-000000000072'
\set eventQuestionsID '90400000-0000-0000-0000-000000000041'
\set eventRefundRequest2ID '00000000-0000-0000-0000-000000000081'
\set eventTicketType1ID '00000000-0000-0000-0000-000000000051'
\set eventTicketType2ID '00000000-0000-0000-0000-000000000052'
\set groupID '00000000-0000-0000-0000-000000000021'
\set questionsAttendeeUserID '90400000-0000-0000-0000-000000000031'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'
\set user4ID '00000000-0000-0000-0000-000000000034'
\set user5ID '00000000-0000-0000-0000-000000000035'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (
    auth_hash,
    email,
    email_verified,
    user_id,
    username,

    company,
    name,
    photo_url,
    registration_status,
    title
)
values
    (gen_random_bytes(32), 'alice@example.com', true, :'user1ID', 'alice', 'Cloud Corp', 'Alice', 'https://e/u1.png', 'registered', 'Principal Engineer'),
    (gen_random_bytes(32), 'bob@example.com', false, :'user2ID', 'bob', null, null, 'https://e/u2.png', 'registered', null),
    (gen_random_bytes(32), 'pending@example.com', false, :'user3ID', 'pending', null, 'Pending Invite', null, 'pre-registered', null),
    (gen_random_bytes(32), 'rejected@example.com', true, :'user4ID', 'rejected', null, 'Rejected Invite', null, 'registered', null),
    (gen_random_bytes(32), 'canceled@example.com', true, :'user5ID', 'canceled', null, 'Canceled Invite', null, 'registered', null),
    (gen_random_bytes(32), 'rq-attendee@test.com', false, :'questionsAttendeeUserID', 'rq-attendee', null, null, null, 'registered', null);

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
    deleted
)
values
    (:'event1ID', 'E1', 'e1', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', 'USD', true, false, false),
    (:'event2ID', 'E2', 'e2', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', 'USD', true, false, false);

-- Event with registration questions used to return attendee answers
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    starts_at,
    registration_questions
) values (
    :'eventQuestionsID',
    :'groupID',
    'Questions Event',
    'questions-event',
    'd',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    '2030-01-01 10:00:00+00',
    '[{"id": "90400000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb
);

-- Ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
)
values
    (:'eventTicketType1ID', :'event1ID', 1, 100, 'General admission'),
    (:'eventTicketType2ID', :'event2ID', 1, 100, 'VIP');

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

-- Attendees
insert into event_attendee (event_id, user_id, status, checked_in, created_at, manually_invited, checked_in_at)
values
    (:'event1ID', :'user1ID', 'confirmed', true, '2024-01-01 00:00:00+00', true, '2024-01-01 10:00:00+00'),
    (:'event1ID', :'user2ID', 'confirmed', false, '2024-01-02 00:00:00+00', false, null),
    (:'event1ID', :'user3ID', 'invitation-pending', false, '2024-01-03 00:00:00+00', true, null),
    (:'event1ID', :'user4ID', 'invitation-rejected', false, '2024-01-04 00:00:00+00', true, null),
    (:'event1ID', :'user5ID', 'invitation-canceled', false, '2024-01-05 00:00:00+00', true, null),
    (:'event2ID', :'user2ID', 'confirmed', true, '2024-01-03 00:00:00+00', false, '2024-01-03 15:00:00+00');

-- Attendee with registration answers returned by attendee search
insert into event_attendee (event_id, user_id, status, registration_answers)
values (
    :'eventQuestionsID',
    :'questionsAttendeeUserID',
    'confirmed',
    '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Attendee answer"}]}'::jsonb
);

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
)
values
    (
        :'eventPurchase1ID',
        2500,
        'USD',
        500,
        'SAVE5',
        :'eventDiscountCode1ID',
        :'event1ID',
        :'eventTicketType1ID',
        'completed',
        'General admission',
        :'user1ID'
    ),
    (
        :'eventPurchase2ID',
        4000,
        'USD',
        0,
        null,
        null,
        :'event2ID',
        :'eventTicketType2ID',
        'refund-requested',
        'VIP',
        :'user2ID'
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

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return attendees for event1 with expected fields and order
select is(
    search_event_attendees(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-000000000041","limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": true,  "created_at": 1704067200, "email": "alice@example.com", "manually_invited": true, "registration_answers": null, "status": "confirmed", "user_id": "00000000-0000-0000-0000-000000000031", "username": "alice", "checked_in_at": 1704103200, "amount_minor": 2500, "company": "Cloud Corp", "currency_code": "USD", "discount_code": "SAVE5", "event_purchase_id": "00000000-0000-0000-0000-000000000071", "name": "Alice", "photo_url": "https://e/u1.png", "refund_request_status": null, "ticket_title": "General admission", "title": "Principal Engineer"},
            {"checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": null, "photo_url": "https://e/u2.png", "refund_request_status": null, "ticket_title": null, "title": null},
            {"checked_in": false, "created_at": 1704240000, "email": "pending@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-pending", "user_id": "00000000-0000-0000-0000-000000000033", "username": "pending", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": "Pending Invite", "photo_url": null, "refund_request_status": null, "ticket_title": null, "title": null},
            {"checked_in": false, "created_at": 1704326400, "email": "rejected@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-rejected", "user_id": "00000000-0000-0000-0000-000000000034", "username": "rejected", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": "Rejected Invite", "photo_url": null, "refund_request_status": null, "ticket_title": null, "title": null}
        ]'::jsonb,
        'notification_recipient_total', 1,
        'total', 4
    ),
    'Should return attendees for event1 with expected fields and order'
);

-- Should return paginated attendees when limit and offset are provided
select is(
    search_event_attendees(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-000000000041","limit":1,"offset":1}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": null, "photo_url": "https://e/u2.png", "refund_request_status": null, "ticket_title": null, "title": null}
        ]'::jsonb,
        'notification_recipient_total', 1,
        'total', 4
    ),
    'Should return paginated attendees when limit and offset are provided'
);

-- Should return full attendee list when pagination is omitted
select is(
    search_event_attendees(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-000000000041"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": true,  "created_at": 1704067200, "email": "alice@example.com", "manually_invited": true, "registration_answers": null, "status": "confirmed", "user_id": "00000000-0000-0000-0000-000000000031", "username": "alice", "checked_in_at": 1704103200, "amount_minor": 2500, "company": "Cloud Corp", "currency_code": "USD", "discount_code": "SAVE5", "event_purchase_id": "00000000-0000-0000-0000-000000000071", "name": "Alice", "photo_url": "https://e/u1.png", "refund_request_status": null, "ticket_title": "General admission", "title": "Principal Engineer"},
            {"checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": null, "photo_url": "https://e/u2.png", "refund_request_status": null, "ticket_title": null, "title": null},
            {"checked_in": false, "created_at": 1704240000, "email": "pending@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-pending", "user_id": "00000000-0000-0000-0000-000000000033", "username": "pending", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": "Pending Invite", "photo_url": null, "refund_request_status": null, "ticket_title": null, "title": null},
            {"checked_in": false, "created_at": 1704326400, "email": "rejected@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-rejected", "user_id": "00000000-0000-0000-0000-000000000034", "username": "rejected", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": "Rejected Invite", "photo_url": null, "refund_request_status": null, "ticket_title": null, "title": null}
        ]'::jsonb,
        'notification_recipient_total', 1,
        'total', 4
    ),
    'Should return full attendee list when pagination is omitted'
);

-- Should return attendees for event2
select is(
    search_event_attendees(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-000000000042","limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": true, "created_at": 1704240000, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "checked_in_at": 1704294000, "amount_minor": 4000, "company": null, "currency_code": "USD", "discount_code": null, "event_purchase_id": "00000000-0000-0000-0000-000000000072", "name": null, "photo_url": "https://e/u2.png", "refund_request_status": "pending", "ticket_title": "VIP", "title": null}
        ]'::jsonb,
        'notification_recipient_total', 0,
        'total', 1
    ),
    'Should return attendees for event2'
);

-- Should return empty list when no event_id provided
select is(
    search_event_attendees(
        :'groupID'::uuid,
        '{"limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'attendees', '[]'::jsonb,
        'notification_recipient_total', 0,
        'total', 0
    ),
    'Should return empty list when no event_id provided'
);

-- Should return empty list for non-existing event
select is(
    search_event_attendees(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-999999999999","limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'attendees', '[]'::jsonb,
        'notification_recipient_total', 0,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- Should include registration answers in attendee search results
select is(
    (
        select attendee->'registration_answers'
        from jsonb_array_elements(
            search_event_attendees(:'groupID'::uuid, jsonb_build_object('event_id', :'eventQuestionsID'::uuid, 'limit', 10, 'offset', 0))::jsonb->'attendees'
        ) attendee
        where attendee->>'user_id' = :'questionsAttendeeUserID'
    ),
    '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Attendee answer"}]}'::jsonb,
    'Should include registration answers in attendee search results'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
