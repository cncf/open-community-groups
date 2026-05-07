-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

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
\set eventRefundRequest2ID '00000000-0000-0000-0000-000000000081'
\set eventTicketType1ID '00000000-0000-0000-0000-000000000051'
\set eventTicketType2ID '00000000-0000-0000-0000-000000000052'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

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
insert into "user" (auth_hash, email, user_id, username, company, name, photo_url, title)
values
    (gen_random_bytes(32), 'alice@example.com', :'user1ID', 'alice', 'Cloud Corp', 'Alice', 'https://e/u1.png', 'Principal Engineer'),
    (gen_random_bytes(32), 'bob@example.com', :'user2ID', 'bob', null, null, 'https://e/u2.png', null);

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
insert into event_attendee (event_id, user_id, checked_in, created_at, checked_in_at)
values
    (:'event1ID', :'user1ID', true,  '2024-01-01 00:00:00+00', '2024-01-01 10:00:00+00'),
    (:'event1ID', :'user2ID', false, '2024-01-02 00:00:00+00', null),
    (:'event2ID', :'user2ID', true,  '2024-01-03 00:00:00+00', '2024-01-03 15:00:00+00');

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
            {"checked_in": true,  "created_at": 1704067200, "user_id": "00000000-0000-0000-0000-000000000031", "username": "alice", "checked_in_at": 1704103200, "amount_minor": 2500, "company": "Cloud Corp", "currency_code": "USD", "discount_code": "SAVE5", "event_purchase_id": "00000000-0000-0000-0000-000000000071", "name": "Alice", "photo_url": "https://e/u1.png", "refund_request_status": null, "ticket_title": "General admission", "title": "Principal Engineer"},
            {"checked_in": false, "created_at": 1704153600, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob",   "checked_in_at": null,       "amount_minor": null, "company": null,        "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": null,    "photo_url": "https://e/u2.png", "refund_request_status": null, "ticket_title": null, "title": null}
        ]'::jsonb,
        'total', 2
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
            {"checked_in": false, "created_at": 1704153600, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "checked_in_at": null, "amount_minor": null, "company": null, "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": null, "photo_url": "https://e/u2.png", "refund_request_status": null, "ticket_title": null, "title": null}
        ]'::jsonb,
        'total', 2
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
            {"checked_in": true,  "created_at": 1704067200, "user_id": "00000000-0000-0000-0000-000000000031", "username": "alice", "checked_in_at": 1704103200, "amount_minor": 2500, "company": "Cloud Corp", "currency_code": "USD", "discount_code": "SAVE5", "event_purchase_id": "00000000-0000-0000-0000-000000000071", "name": "Alice", "photo_url": "https://e/u1.png", "refund_request_status": null, "ticket_title": "General admission", "title": "Principal Engineer"},
            {"checked_in": false, "created_at": 1704153600, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob",   "checked_in_at": null,       "amount_minor": null, "company": null,        "currency_code": null, "discount_code": null, "event_purchase_id": null, "name": null,    "photo_url": "https://e/u2.png", "refund_request_status": null, "ticket_title": null, "title": null}
        ]'::jsonb,
        'total', 2
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
            {"checked_in": true, "created_at": 1704240000, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "checked_in_at": 1704294000, "amount_minor": 4000, "company": null, "currency_code": "USD", "discount_code": null, "event_purchase_id": "00000000-0000-0000-0000-000000000072", "name": null, "photo_url": "https://e/u2.png", "refund_request_status": "pending", "ticket_title": "VIP", "title": null}
        ]'::jsonb,
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
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
