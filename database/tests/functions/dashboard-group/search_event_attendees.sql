-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a2e0000-0000-0000-0000-000000000001'
\set event1ID '3a2e0000-0000-0000-0000-000000000002'
\set event2ID '3a2e0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a2e0000-0000-0000-0000-000000000004'
\set eventDiscountCode1ID '3a2e0000-0000-0000-0000-000000000005'
\set eventPurchase1ID '3a2e0000-0000-0000-0000-000000000006'
\set eventPurchase2ID '3a2e0000-0000-0000-0000-000000000007'
\set eventQuestionsID '3a2e0000-0000-0000-0000-000000000008'
\set eventRefundRequest2ID '3a2e0000-0000-0000-0000-000000000009'
\set eventTicketType1ID '3a2e0000-0000-0000-0000-000000000010'
\set eventTicketType2ID '3a2e0000-0000-0000-0000-000000000011'
\set group2ID '3a2e0000-0000-0000-0000-000000000012'
\set groupCategoryID '3a2e0000-0000-0000-0000-000000000013'
\set groupID '3a2e0000-0000-0000-0000-000000000014'
\set missingEventID '3a2e0000-0000-0000-0000-000000000015'
\set questionsAttendeeUserID '3a2e0000-0000-0000-0000-000000000016'
\set registrationQuestionID '3a2e0000-0000-0000-0000-000000000017'
\set user1ID '3a2e0000-0000-0000-0000-000000000018'
\set user2ID '3a2e0000-0000-0000-0000-000000000019'
\set user3ID '3a2e0000-0000-0000-0000-000000000020'
\set user4ID '3a2e0000-0000-0000-0000-000000000021'
\set user5ID '3a2e0000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'attendee-search-alliance',
    'Attendee Search Alliance',
    'A test alliance for attendee search',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Groups
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values
    (:'groupID', :'allianceID', :'groupCategoryID', 'Attendee Group', 'attendee-group'),
    (:'group2ID', :'allianceID', :'groupCategoryID', 'Other Group', 'other-group');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,

    company,
    name,
    photo_url,
    registration_status,
    title
)
values (
    :'user1ID',
    gen_random_bytes(32),
    'alice@example.com',
    true,
    'alice',
    'Cloud Corp',
    'Alice',
    'https://example.com/alice.png',
    'registered',
    'Principal Engineer'
), (
    :'user2ID',
    gen_random_bytes(32),
    'bob@example.com',
    false,
    'bob',
    null,
    null,
    'https://example.com/bob.png',
    'registered',
    null
), (
    :'user3ID',
    gen_random_bytes(32),
    'pending@example.com',
    false,
    'pending',
    null,
    'Pending Invite',
    null,
    'pre-registered',
    null
), (
    :'user4ID',
    gen_random_bytes(32),
    'rejected@example.com',
    true,
    'rejected',
    null,
    'Rejected Invite',
    null,
    'registered',
    null
), (
    :'user5ID',
    gen_random_bytes(32),
    'canceled@example.com',
    true,
    'canceled',
    null,
    'Canceled Invite',
    null,
    'registered',
    null
), (
    :'questionsAttendeeUserID',
    gen_random_bytes(32),
    'rq-attendee@test.com',
    false,
    'rq-attendee',
    null,
    null,
    null,
    'registered',
    null
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
    deleted
)
values (
    :'event1ID',
    'Attendee Event',
    'attendee-event',
    'An event for attendee search',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    false
), (
    :'event2ID',
    'Refund Event',
    'refund-event',
    'An event for attendee refunds',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    false
);

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
    'An event with registration questions',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    '2030-01-01 10:00:00+00',
    jsonb_build_array(jsonb_build_object(
        'id', :'registrationQuestionID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    ))
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
    :'user3ID',
    false,
    null,
    '2024-01-03 00:00:00+00',
    true,
    'invitation-pending'
), (
    :'event1ID',
    :'user4ID',
    false,
    null,
    '2024-01-04 00:00:00+00',
    true,
    'invitation-rejected'
), (
    :'event1ID',
    :'user5ID',
    false,
    null,
    '2024-01-05 00:00:00+00',
    true,
    'invitation-canceled'
), (
    :'event2ID',
    :'user2ID',
    true,
    '2024-01-03 15:00:00+00',
    '2024-01-03 00:00:00+00',
    false,
    'confirmed'
);

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
        jsonb_build_object('event_id', :'event1ID'::uuid, 'limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": true,  "created_at": 1704067200, "email": "alice@example.com", "manually_invited": true, "registration_answers": null, "status": "confirmed", "user_id": "3a2e0000-0000-0000-0000-000000000018", "username": "alice", "checked_in_at": 1704103200, "amount_minor": 2500, "company": "Cloud Corp", "currency_code": "USD", "discount_code": "SAVE5", "event_purchase_id": "3a2e0000-0000-0000-0000-000000000006", "name": "Alice", "photo_url": "https://example.com/alice.png", "refund_request_status": null, "ticket_title": "General admission", "title": "Principal Engineer"},
            {"checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": null, "photo_url": "https://example.com/bob.png", "refund_request_status": null, "ticket_title": null, "title": null},
            {"checked_in": false, "created_at": 1704240000, "email": "pending@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-pending", "user_id": "3a2e0000-0000-0000-0000-000000000020", "username": "pending", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": "Pending Invite", "photo_url": null, "refund_request_status": null, "ticket_title": null, "title": null},
            {"checked_in": false, "created_at": 1704326400, "email": "rejected@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-rejected", "user_id": "3a2e0000-0000-0000-0000-000000000021", "username": "rejected", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": "Rejected Invite", "photo_url": null, "refund_request_status": null, "ticket_title": null, "title": null}
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
        jsonb_build_object('event_id', :'event1ID'::uuid, 'limit', 1, 'offset', 1)
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": null, "photo_url": "https://example.com/bob.png", "refund_request_status": null, "ticket_title": null, "title": null}
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
        jsonb_build_object('event_id', :'event1ID'::uuid)
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": true,  "created_at": 1704067200, "email": "alice@example.com", "manually_invited": true, "registration_answers": null, "status": "confirmed", "user_id": "3a2e0000-0000-0000-0000-000000000018", "username": "alice", "checked_in_at": 1704103200, "amount_minor": 2500, "company": "Cloud Corp", "currency_code": "USD", "discount_code": "SAVE5", "event_purchase_id": "3a2e0000-0000-0000-0000-000000000006", "name": "Alice", "photo_url": "https://example.com/alice.png", "refund_request_status": null, "ticket_title": "General admission", "title": "Principal Engineer"},
            {"checked_in": false, "created_at": 1704153600, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": null, "photo_url": "https://example.com/bob.png", "refund_request_status": null, "ticket_title": null, "title": null},
            {"checked_in": false, "created_at": 1704240000, "email": "pending@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-pending", "user_id": "3a2e0000-0000-0000-0000-000000000020", "username": "pending", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": "Pending Invite", "photo_url": null, "refund_request_status": null, "ticket_title": null, "title": null},
            {"checked_in": false, "created_at": 1704326400, "email": "rejected@example.com", "manually_invited": true, "registration_answers": null, "status": "invitation-rejected", "user_id": "3a2e0000-0000-0000-0000-000000000021", "username": "rejected", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": "Rejected Invite", "photo_url": null, "refund_request_status": null, "ticket_title": null, "title": null}
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
        jsonb_build_object('event_id', :'event2ID'::uuid, 'limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": true, "created_at": 1704240000, "email": "bob@example.com", "manually_invited": false, "registration_answers": null, "status": "confirmed", "user_id": "3a2e0000-0000-0000-0000-000000000019", "username": "bob", "checked_in_at": 1704294000, "amount_minor": 4000, "company": null, "currency_code": "USD", "discount_code": null, "event_purchase_id": "3a2e0000-0000-0000-0000-000000000007", "name": null, "photo_url": "https://example.com/bob.png", "refund_request_status": "pending", "ticket_title": "VIP", "title": null}
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
        jsonb_build_object('event_id', :'missingEventID'::uuid, 'limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'attendees', '[]'::jsonb,
        'notification_recipient_total', 0,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- Should return empty list when event belongs to another group
select is(
    search_event_attendees(
        :'group2ID'::uuid,
        jsonb_build_object('event_id', :'event1ID'::uuid, 'limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'attendees', '[]'::jsonb,
        'notification_recipient_total', 0,
        'total', 0
    ),
    'Should return empty list when event belongs to another group'
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
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', :'registrationQuestionID',
            'value', 'Attendee answer'
        ))
    ),
    'Should include registration answers in attendee search results'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
