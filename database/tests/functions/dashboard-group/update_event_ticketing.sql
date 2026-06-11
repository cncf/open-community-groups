-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(42);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set category1ID '3a3c0000-0000-0000-0000-000000000001'
\set community1ID '3a3c0000-0000-0000-0000-000000000002'
\set event13ID '3a3c0000-0000-0000-0000-000000000003'
\set event14ID '3a3c0000-0000-0000-0000-000000000004'
\set event15ID '3a3c0000-0000-0000-0000-000000000005'
\set event16ID '3a3c0000-0000-0000-0000-000000000006'
\set event17ID '3a3c0000-0000-0000-0000-000000000007'
\set event19ID '3a3c0000-0000-0000-0000-000000000008'
\set event20ID '3a3c0000-0000-0000-0000-000000000009'
\set event21ID '3a3c0000-0000-0000-0000-000000000010'
\set event22ID '3a3c0000-0000-0000-0000-000000000011'
\set event23ID '3a3c0000-0000-0000-0000-000000000012'
\set event24ID '3a3c0000-0000-0000-0000-000000000013'
\set eventOverCapacityID '3a3c0000-0000-0000-0000-000000000014'
\set eventQuestionsAnsweredID '3a3c0000-0000-0000-0000-000000000015'
\set eventQuestionsID '3a3c0000-0000-0000-0000-000000000016'
\set eventQuestionsPublishedID '3a3c0000-0000-0000-0000-000000000017'
\set group1ID '3a3c0000-0000-0000-0000-000000000018'
\set questionsAttendeeUserID '3a3c0000-0000-0000-0000-000000000019'
\set questionsCategoryID '3a3c0000-0000-0000-0000-000000000020'
\set questionsCommunityID '3a3c0000-0000-0000-0000-000000000021'
\set questionsEventCategoryID '3a3c0000-0000-0000-0000-000000000022'
\set questionsGroupID '3a3c0000-0000-0000-0000-000000000023'
\set questionsOrganizerUserID '3a3c0000-0000-0000-0000-000000000024'
\set user1ID '3a3c0000-0000-0000-0000-000000000025'
\set user2ID '3a3c0000-0000-0000-0000-000000000026'
\set user3ID '3a3c0000-0000-0000-0000-000000000027'
\set user4ID '3a3c0000-0000-0000-0000-000000000028'
\set user5ID '3a3c0000-0000-0000-0000-000000000029'

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
    :'community1ID',
    'test-community',
    'Test Community',
    'A test community for testing purposes',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Community for registration-question update tests
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'questionsCommunityID',
    'update-questions-community',
    'Update Questions Community',
    'Desc',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Users
insert into "user" (user_id, auth_hash, email, username, name) values
    (:'user1ID', 'hash1', 'host1@example.com', 'host1', 'Host One'),
    (:'user2ID', 'hash2', 'host2@example.com', 'host2', 'Host Two'),
    (:'user3ID', 'hash3', 'speaker1@example.com', 'speaker1', 'Speaker One'),
    (:'user4ID', 'hash4', 'waitlist1@example.com', 'waitlist1', 'Waitlist One'),
    (:'user5ID', 'hash5', 'waitlist2@example.com', 'waitlist2', 'Waitlist Two'),
    (:'questionsOrganizerUserID', 'rq-hash-1', 'rq-organizer@example.com', 'rq-organizer', null),
    (:'questionsAttendeeUserID', 'rq-hash-2', 'rq-attendee@example.com', 'rq-attendee', null);

-- Event Category
insert into event_category (event_category_id, name, community_id)
values
    (:'category1ID', 'Conference', :'community1ID'),
    (:'questionsEventCategoryID', 'General', :'questionsCommunityID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values ('3a3c0000-0000-0000-0000-000000000030', 'Technology', :'community1ID');

-- Group category for registration-question update tests
insert into group_category (group_category_id, name, community_id)
values (:'questionsCategoryID', 'Technology', :'questionsCommunityID');

-- Group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'group1ID',
    :'community1ID',
    'Test Group',
    'abc1234',
    'A test group',
    '3a3c0000-0000-0000-0000-000000000030'
);

-- Group for registration-question update tests
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug
) values (
    :'questionsGroupID',
    :'questionsCommunityID',
    :'questionsCategoryID',
    'Update Questions Group',
    'update-questions-group'
);

-- Events used to update and lock registration questions
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
    :'questionsGroupID',
    'Draft Questions Event',
    'draft-questions-event',
    'Desc',
    'UTC',
    :'questionsEventCategoryID',
    'in-person',
    false,
    '2030-01-01 10:00:00+00',
    '[]'::jsonb
), (
    :'eventQuestionsPublishedID',
    :'questionsGroupID',
    'Published Questions Event',
    'published-questions-event',
    'Desc',
    'UTC',
    :'questionsEventCategoryID',
    'in-person',
    true,
    '2030-01-01 10:00:00+00',
    jsonb_build_array(jsonb_build_object(
        'id', '3a3c0000-0000-0000-0000-000000000031',
        'kind', 'free-text',
        'options', '[]'::jsonb,
        'prompt', 'Original',
        'required', true
    ))
), (
    :'eventQuestionsAnsweredID',
    :'questionsGroupID',
    'Answered Questions Event',
    'answered-questions-event',
    'Desc',
    'UTC',
    :'questionsEventCategoryID',
    'in-person',
    false,
    '2030-01-01 10:00:00+00',
    jsonb_build_array(jsonb_build_object(
        'id', '3a3c0000-0000-0000-0000-000000000031',
        'kind', 'free-text',
        'options', '[]'::jsonb,
        'prompt', 'Original',
        'required', true
    ))
);

-- Published event for waitlist promotion checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    waitlist_enabled
) values (
    :'event13ID',
    :'group1ID',
    'Published Waitlist Event',
    'published-waitlist',
    'Published event for waitlist promotion checks',
    'UTC',
    :'category1ID',
    'in-person',
    1,
    true,
    '2030-02-01 10:00:00+00',
    true
);

-- Published event used for attendee floor validation checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at
) values (
    :'event14ID',
    :'group1ID',
    'Capacity Validation Event',
    'capacity-validation',
    'Published event for attendee floor validation checks',
    'America/New_York',
    :'category1ID',
    'in-person',
    3,
    true,
    '2030-02-10 10:00:00-05'
);

-- Published event used for waitlist promotion on capacity increase
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    ends_at,
    waitlist_enabled
) values (
    :'event15ID',
    :'group1ID',
    'Waitlist Promotion Event',
    'waitlist-promotion',
    'Published event for waitlist capacity increase promotion checks',
    'America/New_York',
    :'category1ID',
    'in-person',
    3,
    true,
    '2030-03-01 10:00:00-05',
    '2030-03-01 12:00:00-05',
    true
);

-- Published event used when waitlist is disabled for new joins
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    waitlist_enabled
) values (
    :'event16ID',
    :'group1ID',
    'Waitlist Disabled Event',
    'waitlist-disabled',
    'Published event for disabled waitlist promotion checks',
    'UTC',
    :'category1ID',
    'in-person',
    2,
    true,
    '2030-02-16 10:00:00+00',
    true
);

-- Published event already over capacity because of a confirmed manual invitation
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at
) values (
    :'eventOverCapacityID',
    :'group1ID',
    'Manual Invite Over Capacity Event',
    'manual-invite-over-capacity',
    'Published event for unchanged over-capacity save checks',
    'UTC',
    :'category1ID',
    'in-person',
    2,
    true,
    '2030-02-12 10:00:00+00'
);

-- Published event used when capacity becomes unlimited
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    waitlist_enabled
) values (
    :'event17ID',
    :'group1ID',
    'Unlimited Event',
    'unlimited-event',
    'Published event for unlimited capacity promotion checks',
    'UTC',
    :'category1ID',
    'in-person',
    1,
    true,
    '2030-02-17 10:00:00+00',
    true
);

-- Published event used for ticketing conversion without waitlist promotion
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    ends_at,
    waitlist_enabled
) values (
    :'event20ID',
    :'group1ID',
    'Ticketing Conversion Event',
    'ticketing-conversion',
    'Published event used to verify ticketing conversion does not promote waitlist users',
    'America/New_York',
    :'category1ID',
    'in-person',
    1,
    true,
    '2030-04-01 10:00:00-04',
    '2030-04-01 12:00:00-04',
    true
);

-- Unticketed event used for ticketing payload validation checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'event22ID',
    :'group1ID',
    'Ticketing Payload Event',
    'ticketing-payload',
    'Unticketed event used for ticketing payload validation checks',
    'UTC',
    :'category1ID',
    'virtual'
);

-- Published event used for ticketing conversion waitlist checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    ends_at,
    waitlist_enabled
) values (
    :'event23ID',
    :'group1ID',
    'Ticketing Waitlist Event',
    'ticketing-waitlist',
    'Published event used for ticketing conversion waitlist checks',
    'UTC',
    :'category1ID',
    'in-person',
    1,
    true,
    '2030-05-01 10:00:00+00',
    '2030-05-01 12:00:00+00',
    true
);

-- Approval-required event used for invitation request transition checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    attendee_approval_required
) values (
    :'event24ID',
    :'group1ID',
    'Approval Request Event',
    'approval-request',
    'Approval-required event used for invitation request checks',
    'UTC',
    :'category1ID',
    'virtual',
    true
);

-- Paid event used for ticketing preservation checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    payment_currency_code
) values (
    :'event19ID',
    :'group1ID',
    'Paid Event',
    'paid-event',
    'Event seeded for ticketing preservation tests',
    'UTC',
    :'category1ID',
    'virtual',
    10,
    'USD'
);

-- Paid event used for purchased ticketing guard checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    payment_currency_code
) values (
    :'event21ID',
    :'group1ID',
    'Protected Paid Event',
    'protected-paid-event',
    'Paid event used for purchased ticketing guard checks',
    'UTC',
    :'category1ID',
    'virtual',
    10,
    'USD'
);

-- Separate event used only for ticketing ownership checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    payment_currency_code
) values (
    '3a3c0000-0000-0000-0000-000000000032'::uuid,
    :'group1ID',
    'Other Paid Event',
    'other-paid-event',
    'Event seeded for ticketing ownership tests',
    'UTC',
    :'category1ID',
    'virtual',
    'USD'
);

insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000033'::uuid,
    true,
    :'event19ID',
    1,
    10,
    'General'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '3a3c0000-0000-0000-0000-000000000034'::uuid,
    2500,
    '3a3c0000-0000-0000-0000-000000000033'::uuid
);

insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000035'::uuid,
    true,
    500,
    'SAVE20',
    :'event19ID',
    'fixed_amount',
    'Launch'
);

insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000036'::uuid,
    true,
    :'event21ID',
    1,
    10,
    'Protected General'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '3a3c0000-0000-0000-0000-000000000037'::uuid,
    2500,
    '3a3c0000-0000-0000-0000-000000000036'::uuid
);

insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000038'::uuid,
    true,
    :'event21ID',
    2,
    5,
    'Protected VIP'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '3a3c0000-0000-0000-0000-000000000039'::uuid,
    5000,
    '3a3c0000-0000-0000-0000-000000000038'::uuid
);

insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title,
    total_available
) values (
    '3a3c0000-0000-0000-0000-000000000040'::uuid,
    true,
    500,
    'PROTECT5',
    :'event21ID',
    'fixed_amount',
    'Protected launch',
    5
);

-- Ticketing rows on a different event used for ownership checks
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000041'::uuid,
    true,
    '3a3c0000-0000-0000-0000-000000000032'::uuid,
    1,
    25,
    'Other Event General'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '3a3c0000-0000-0000-0000-000000000042'::uuid,
    3000,
    '3a3c0000-0000-0000-0000-000000000041'::uuid
);

insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    '3a3c0000-0000-0000-0000-000000000043'::uuid,
    true,
    250,
    'OTHER25',
    '3a3c0000-0000-0000-0000-000000000032'::uuid,
    'fixed_amount',
    'Other launch'
);

insert into event_purchase (
    amount_minor,
    currency_code,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    2500,
    'USD',
    'PROTECT5',
    '3a3c0000-0000-0000-0000-000000000040'::uuid,
    :'event21ID',
    '3a3c0000-0000-0000-0000-000000000036'::uuid,
    'completed',
    'Protected General',
    :'user1ID'
);

-- Event Attendees (for capacity validation and waitlist promotion tests)
insert into event_attendee (event_id, user_id) values
    (:'event13ID', :'user2ID'),
    (:'event14ID', :'user1ID'),
    (:'event14ID', :'user2ID'),
    (:'event14ID', :'user3ID'),
    (:'event15ID', :'user1ID'),
    (:'event15ID', :'user2ID'),
    (:'event15ID', :'user3ID'),
    (:'event16ID', :'user2ID'),
    (:'event16ID', :'user3ID'),
    (:'event17ID', :'user2ID'),
    (:'event20ID', :'user1ID');

-- Over-capacity event attendees with one organizer-controlled manual seat
insert into event_attendee (event_id, user_id, manually_invited, status) values
    (:'eventOverCapacityID', :'user1ID', false, 'confirmed'),
    (:'eventOverCapacityID', :'user2ID', false, 'confirmed'),
    (:'eventOverCapacityID', :'user3ID', true, 'confirmed');

-- Attendee with answers that lock registration questions
insert into event_attendee (event_id, user_id, registration_answers, status)
values (
    :'eventQuestionsAnsweredID',
    :'questionsAttendeeUserID',
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', '3a3c0000-0000-0000-0000-000000000031',
            'value', 'Answer'
        ))
    ),
    'confirmed'
);

-- Event Waitlist (for waitlist promotion tests)
insert into event_waitlist (event_id, user_id, created_at) values
    (:'event13ID', :'user3ID', current_timestamp),
    (:'event15ID', :'user4ID', current_timestamp),
    (:'event15ID', :'user5ID', current_timestamp + interval '1 minute'),
    (:'event16ID', :'user1ID', current_timestamp + interval '2 minutes'),
    (:'event17ID', :'user4ID', current_timestamp + interval '3 minutes'),
    (:'event17ID', :'user5ID', current_timestamp + interval '4 minutes'),
    (:'event20ID', :'user4ID', current_timestamp + interval '5 minutes'),
    (:'event23ID', :'user5ID', current_timestamp + interval '6 minutes');

-- Event invitation requests (for attendee approval transition tests)
insert into event_invitation_request (event_id, user_id)
values (:'event24ID', :'user5ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should preserve ticketing fields when payload omits payment controls
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "meeting_requested": false
        }'::jsonb
    )$$,
    'Should preserve ticketing fields when payload omits payment controls'
);
select is(
    (
        select jsonb_build_object(
            'discount_codes', list_event_discount_codes(event_id),
            'payment_currency_code', payment_currency_code,
            'ticket_types', list_event_ticket_types(event_id)
        )
        from event
        where event_id = :'event19ID'::uuid
    ),
    '{
        "discount_codes": [
            {
                "active": true,
                "amount_minor": 500,
                "available_override_active": false,
                "code": "SAVE20",
                "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000035",
                "kind": "fixed_amount",
                "title": "Launch"
            }
        ],
        "payment_currency_code": "USD",
        "ticket_types": [
            {
                "active": true,
                "current_price": {
                    "amount_minor": 2500
                },
                "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000033",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2500,
                        "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000034"
                    }
                ],
                "remaining_seats": 10,
                "seats_total": 10,
                "sold_out": false,
                "title": "General"
            }
        ]
    }'::jsonb,
    'Should keep ticketing fields when payload omits payment controls'
);
select is(
    (select capacity from event where event_id = :'event19ID'::uuid),
    10,
    'Should preserve derived capacity when payload omits payment controls'
);

-- Should throw error when discount codes remain without ticket types
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": null,
            "ticket_types": null
        }'::jsonb
    )$$,
    'discount_codes require ticket_types',
    'Should throw error when discount codes remain after ticket types are cleared'
);

-- Should throw error when payment currency remains without ticket types
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "discount_codes": null,
            "ticket_types": null
        }'::jsonb
    )$$,
    'payment_currency_code requires ticket_types',
    'Should throw error when payment currency remains after ticket types are cleared'
);

-- Should throw error when a ticket type identifier belongs to another event
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000041",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000044"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'ticket type does not belong to event',
    'Should reject ticket types whose identifiers belong to another event'
);

-- Should throw error when a ticket price window identifier belongs to another event
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000033",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000042"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'ticket price window does not belong to event',
    'Should reject ticket price windows whose identifiers belong to another event'
);

-- Should throw error when a ticket price window identifier belongs to another ticket type
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000036",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000039"
                        }
                    ],
                    "seats_total": 10,
                    "title": "Protected General"
                },
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000038",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000039"
                        }
                    ],
                    "seats_total": 5,
                    "title": "Protected VIP"
                }
            ]
        }'::jsonb
    )$$,
    'ticket price window does not belong to ticket type',
    'Should reject ticket price windows whose identifiers belong to another ticket type'
);

-- Should throw error when a discount code identifier belongs to another event
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "discount_codes": [
                {
                    "active": true,
                    "amount_minor": 250,
                    "code": "OTHER25",
                    "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000043",
                    "kind": "fixed_amount",
                    "title": "Other launch"
                }
            ],
            "kind_id": "virtual"
        }'::jsonb
    )$$,
    'discount code does not belong to event',
    'Should reject discount codes whose identifiers belong to another event'
);

-- Should throw error when ticketed events omit payment_currency_code
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000011'::uuid,
        '{
            "name": "Ticketing Payload Event",
            "description": "Unticketed event used for ticketing payload validation checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000047",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000048"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'ticketed events require payment_currency_code',
    'Should reject ticketed events when payment_currency_code is omitted'
);

-- Should throw error when waitlist remains enabled for ticketed events
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000011'::uuid,
        '{
            "name": "Ticketing Payload Event",
            "description": "Unticketed event used for ticketing payload validation checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000049",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000050"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ],
            "waitlist_enabled": true
        }'::jsonb
    )$$,
    'waitlist cannot be enabled for ticketed events',
    'Should reject ticketed events when waitlist_enabled stays true'
);

-- Should reject disabling attendee approval while invitation requests are pending
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000013'::uuid,
        '{
            "name": "Approval Request Event",
            "description": "Approval-required event used for invitation request checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "attendee_approval_required": false
        }'::jsonb
    )$$,
    'approval-required events with pending invitation requests cannot disable approval',
    'Should reject disabling attendee approval while invitation requests are pending'
);

-- Should reject enabling attendee approval while waitlist entries exist
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000012'::uuid,
        '{
            "name": "Ticketing Waitlist Event",
            "description": "Published event used for ticketing conversion waitlist checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "attendee_approval_required": true,
            "capacity": 1,
            "ends_at": "2030-05-01T12:00:00",
            "starts_at": "2030-05-01T10:00:00",
            "waitlist_enabled": false
        }'::jsonb
    )$$,
    'approval-required events cannot have existing waitlist entries',
    'Should reject enabling attendee approval while queued users already exist'
);

-- Should throw error when ticket seats are reduced below purchased inventory
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000036",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000037"
                        }
                    ],
                    "seats_total": 0,
                    "title": "Protected General"
                }
            ]
        }'::jsonb
    )$$,
    'ticket type seats_total (0) cannot be less than current number of purchased seats (1)',
    'Should reject seat totals below the current purchased inventory for a ticket type'
);

-- Should throw error when purchased ticket types are removed
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": []
        }'::jsonb
    )$$,
    'ticket types with purchases cannot be removed; deactivate them instead',
    'Should reject removing ticket types that already have purchases'
);

-- Should throw error when discount code total_available drops below redemptions
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "discount_codes": [
                {
                    "active": true,
                    "amount_minor": 500,
                    "code": "PROTECT5",
                    "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000040",
                    "kind": "fixed_amount",
                    "title": "Protected launch",
                    "total_available": 0
                }
            ],
            "kind_id": "virtual"
        }'::jsonb
    )$$,
    'discount code total_available cannot be less than existing redemptions',
    'Should reject lowering discount code availability below existing redemptions'
);

-- Should throw error when redeemed discount codes are removed
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "discount_codes": [],
            "kind_id": "virtual"
        }'::jsonb
    )$$,
    'discount codes with redemptions cannot be removed; deactivate them instead',
    'Should reject removing discount codes that already have redemptions'
);

-- Should throw error when capacity is reduced below attendee count
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Capacity Validation Event", "description": "Test", "timezone": "America/New_York", "category_id": "3a3c0000-0000-0000-0000-000000000001", "kind_id": "in-person", "capacity": 2, "starts_at": "2030-02-10T10:00:00"}'::jsonb
    )$$,
    'event capacity (2) cannot be less than current number of attendees (3)',
    'Should throw error when capacity is reduced below attendee count'
);

-- Should allow saving an event already over capacity from accepted manual invitations
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000014'::uuid,
        '{"name": "Manual Invite Over Capacity Event", "description": "Saved while over capacity", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000001", "kind_id": "in-person", "capacity": 2, "starts_at": "2030-02-12T10:00:00"}'::jsonb
    )$$,
    'Should allow saving an event already over capacity from accepted manual invitations'
);

select is(
    (select description from event where event_id = :'eventOverCapacityID'::uuid),
    'Saved while over capacity',
    'Should persist updates when over-capacity event capacity is unchanged'
);

-- Should reject ticketing conversion when the event already has attendees
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000004'::uuid,
        '{
            "name": "Capacity Validation Event",
            "description": "Ticketed capacity validation",
            "timezone": "America/New_York",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "capacity": 100,
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000035",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000055"
                        }
                    ],
                    "seats_total": 2,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'ticketed events require an empty attendee list',
    'Should reject ticketing conversion before ticket-derived capacity can undercount attendees'
);

-- Should succeed when capacity equals attendee count
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Capacity Validation Event", "description": "Test capacity equals", "timezone": "America/New_York", "category_id": "3a3c0000-0000-0000-0000-000000000001", "kind_id": "in-person", "capacity": 3, "starts_at": "2030-02-10T10:00:00"}'::jsonb
    )$$,
    'Should succeed when capacity equals attendee count'
);

-- Should succeed when capacity exceeds attendee count
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Capacity Validation Event", "description": "Test capacity exceeds", "timezone": "America/New_York", "category_id": "3a3c0000-0000-0000-0000-000000000001", "kind_id": "in-person", "capacity": 100, "starts_at": "2030-02-10T10:00:00"}'::jsonb
    )$$,
    'Should succeed when capacity exceeds attendee count'
);

-- Should promote waitlisted users when increasing capacity on a waitlist-enabled event
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'event15ID'::uuid,
        '{
            "name": "Waitlist Promotion Event",
            "description": "Test capacity promotion",
            "timezone": "America/New_York",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "capacity": 5,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T12:00:00",
            "waitlist_enabled": true
        }'::jsonb
    )::jsonb,
    format('["%s","%s"]', :'user4ID', :'user5ID')::jsonb,
    'Should return promoted waitlist user ids when capacity increase opens seats'
);

-- Should move promoted users into attendees and empty the waitlist
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'event15ID'::uuid
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                from event_waitlist
                where event_id = :'event15ID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s","%s","%s","%s"],"waitlist":[]}',
        :'user1ID', :'user2ID', :'user3ID', :'user4ID', :'user5ID'
    )::jsonb,
    'Should move promoted waitlist users into attendees when capacity increases'
);

-- Should reject ticketing conversion when attendees already exist, even if the event also has a waitlist
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000009'::uuid,
        '{
            "name": "Ticketing Conversion Event",
            "description": "Published event used to verify ticketing conversion does not promote waitlist users",
            "timezone": "America/New_York",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "capacity": 99,
            "ends_at": "2030-04-01T12:00:00",
            "payment_currency_code": "USD",
            "starts_at": "2030-04-01T10:00:00",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000045",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000046"
                        }
                    ],
                    "seats_total": 2,
                    "title": "General admission"
                }
            ]
        }'::jsonb
    )$$,
    'ticketed events require an empty attendee list',
    'Should reject ticketing conversion when attendees and queued users still exist'
);

-- Should reject ticketing conversion when the event already has a waitlist
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000012'::uuid,
        '{
            "name": "Ticketing Waitlist Event",
            "description": "Published event used for ticketing conversion waitlist checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "capacity": 99,
            "ends_at": "2030-05-01T12:00:00",
            "payment_currency_code": "USD",
            "starts_at": "2030-05-01T10:00:00",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000051",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000052"
                        }
                    ],
                    "seats_total": 2,
                    "title": "General admission"
                }
            ]
        }'::jsonb
    )$$,
    'ticketed events cannot have existing waitlist entries',
    'Should reject ticketing conversion when queued users already exist'
);

-- Should reject ticketing conversion when the event already has attendees
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000004'::uuid,
        '{
            "name": "Capacity Validation Event",
            "description": "Published event for attendee floor validation checks",
            "timezone": "America/New_York",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "capacity": 99,
            "ends_at": "2030-02-10T12:00:00",
            "payment_currency_code": "USD",
            "starts_at": "2030-02-10T10:00:00",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000053",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000054"
                        }
                    ],
                    "seats_total": 3,
                    "title": "General admission"
                }
            ]
        }'::jsonb
    )$$,
    'ticketed events require an empty attendee list',
    'Should reject ticketing conversion when confirmed attendees already exist'
);

-- Should keep the event unticketed when attendee-based conversion is rejected
select is(
    list_event_ticket_types(:'event14ID'::uuid),
    null,
    'Should leave ticket types untouched when attendee-based conversion is rejected'
);

-- Should keep attendees and waitlist unchanged when rejected conversion leaves the event untouched
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'event20ID'::uuid
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                from event_waitlist
                where event_id = :'event20ID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s"],"waitlist":["%s"]}',
        :'user1ID', :'user4ID'
    )::jsonb,
    'Should leave existing waitlist entries untouched when ticketing conversion is rejected'
);

-- Should promote waitlisted users for a published event when capacity increases
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'event13ID'::uuid,
        format(
            '{
                "name": "Published Waitlist Event",
                "description": "Published event for waitlist promotion checks",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "capacity": 2,
                "starts_at": "2030-02-01T10:00:00",
                "waitlist_enabled": true
            }',
            :'category1ID'
        )::jsonb
    )::jsonb,
    format('["%s"]', :'user3ID')::jsonb,
    'Should return promoted waitlist user ids when a published event gains capacity'
);

-- Should move promoted users into attendees for a published event
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'event13ID'::uuid
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                from event_waitlist
                where event_id = :'event13ID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s"],"waitlist":[]}',
        :'user2ID', :'user3ID'
    )::jsonb,
    'Should move promoted users into attendees when a published event gains capacity'
);

-- Should continue promoting queued users when waitlist is disabled for new joins
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'event16ID'::uuid,
        format(
            '{
                "name": "Waitlist Disabled Event",
                "description": "Published event for disabled waitlist promotion checks",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "capacity": 3,
                "starts_at": "2030-02-16T10:00:00",
                "waitlist_enabled": false
            }',
            :'category1ID'
        )::jsonb
    )::jsonb,
    format('["%s"]', :'user1ID')::jsonb,
    'Should promote existing waitlist users even when waitlist is disabled for new joins'
);

-- Should leave the queue empty after promoting existing users with waitlist disabled
select is(
    (select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb) from event_waitlist where event_id = :'event16ID'::uuid),
    '[]'::jsonb,
    'Should empty the remaining waitlist after promotion when waitlist is disabled'
);

-- Should promote all queued users when capacity becomes unlimited
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'event17ID'::uuid,
        format(
            '{
                "name": "Unlimited Event",
                "description": "Published event for unlimited capacity promotion checks",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "capacity": null,
                "starts_at": "2030-02-17T10:00:00",
                "waitlist_enabled": false
            }',
            :'category1ID'
        )::jsonb
    )::jsonb,
    format('["%s","%s"]', :'user4ID', :'user5ID')::jsonb,
    'Should promote the full queue when capacity becomes unlimited'
);

-- Should empty the queue when capacity becomes unlimited
select is(
        (
            select jsonb_build_object(
                'attendees', (
                    select jsonb_agg(user_id order by user_id)
                    from event_attendee
                    where event_id = :'event17ID'::uuid
                ),
                'waitlist', (
                    select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                    from event_waitlist
                    where event_id = :'event17ID'::uuid
                )
            )
        ),
    format(
        '{"attendees":["%s","%s","%s"],"waitlist":[]}',
        :'user2ID', :'user4ID', :'user5ID'
    )::jsonb,
    'Should move all waitlisted users into attendees when capacity becomes unlimited'
);

-- Should update registration questions while the event is unpublished
select lives_ok(
    $$
        select update_event(
            '3a3c0000-0000-0000-0000-000000000024'::uuid,
            '3a3c0000-0000-0000-0000-000000000023'::uuid,
            '3a3c0000-0000-0000-0000-000000000016'::uuid,
            '{"name": "Draft Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Original", "required": true, "options": []}]}'::jsonb
        )
    $$,
    'Should update registration questions while the event is unpublished'
);

-- Should store updated registration questions
select is(
    (
        select registration_questions
        from event
        where event_id = :'eventQuestionsID'::uuid
    ),
    '[{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Original", "required": true, "options": []}]'::jsonb,
    'Should store updated registration questions'
);

-- Should validate registration questions when updating an event
select throws_ok(
    $$select update_event(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000016'::uuid,
        '{"name": "Draft Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "bad", "kind": "free-text", "prompt": "Invalid", "required": true, "options": []}]}'::jsonb
    )$$,
    'questionnaire question id must be a uuid',
    'Should validate registration questions when updating an event'
);

-- Should update registration questions after publish when no answers exist
select lives_ok(
    $$select update_event(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000017'::uuid,
        '{"name": "Published Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Changed", "required": true, "options": []}]}'::jsonb
    )$$,
    'Should update registration questions after publish when no answers exist'
);

-- Should preserve registration questions when answers exist and questions are omitted
select lives_ok(
    $$select update_event(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000015'::uuid,
        '{"name": "Answered Questions Event Updated", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z"}'::jsonb
    )$$,
    'Should preserve registration questions when answers exist and questions are omitted'
);

-- Should reject registration question changes after answers exist
select throws_ok(
    $$select update_event(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000015'::uuid,
        '{"name": "Answered Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Changed", "required": true, "options": []}]}'::jsonb
    )$$,
    'registration questions cannot be changed after attendees have submitted answers',
    'Should reject registration question changes after answers exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
