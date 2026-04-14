-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000021'
\set eventProtectedID '00000000-0000-0000-0000-000000000022'
\set groupCategoryID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000041'
\set ticketType1ID '00000000-0000-0000-0000-000000000051'
\set ticketType2ID '00000000-0000-0000-0000-000000000052'
\set ticketType3ID '00000000-0000-0000-0000-000000000053'
\set ticketTypeProtectedID '00000000-0000-0000-0000-000000000054'
\set userID '00000000-0000-0000-0000-000000000061'
\set window1CurrentID '00000000-0000-0000-0000-000000000071'
\set window1OldID '00000000-0000-0000-0000-000000000072'
\set window3ID '00000000-0000-0000-0000-000000000073'
\set windowProtectedID '00000000-0000-0000-0000-000000000074'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'community-1', 'Community 1', 'Test community', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Group 1', 'group-1');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified)
values (:'userID', 'test_hash', 'ticket-user@example.test', 'ticket-user', true);

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values
    (
        :'eventID',
        :'groupID',
        'Ticket Types Event',
        'ticket-types-event',
        'Event used for ticket type sync tests',
        'UTC',
        :'eventCategoryID',
        'virtual'
    ),
    (
        :'eventProtectedID',
        :'groupID',
        'Protected Ticket Types Event',
        'protected-ticket-types-event',
        'Event used for protected ticket type checks',
        'UTC',
        :'eventCategoryID',
        'virtual'
    );

-- Event ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values
    (:'ticketType1ID', :'eventID', 1, 10, 'General admission'),
    (:'ticketType2ID', :'eventID', 2, 5, 'VIP pass'),
    (:'ticketTypeProtectedID', :'eventProtectedID', 1, 2, 'Protected pass');

insert into event_ticket_type (
    event_ticket_type_id,
    description,
    event_id,
    "order",
    seats_total,
    title
) values
    (:'ticketType3ID', 'Workshop access', :'eventID', 3, 8, 'Workshop pass');

-- Event ticket price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'window1CurrentID', 2000, :'ticketType1ID'),
    (:'window1OldID', 2500, :'ticketType1ID'),
    (:'windowProtectedID', 3000, :'ticketTypeProtectedID');

-- Event purchase
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    3000,
    'USD',
    :'eventProtectedID',
    :'ticketTypeProtectedID',
    'completed',
    'Protected pass',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should upsert payload ticket types and remove omitted ticket types
select lives_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[
                {
                    "event_ticket_type_id": "%s",
                    "active": false,
                    "description": "Updated general admission",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2200,
                            "event_ticket_price_window_id": "%s"
                        }
                    ],
                    "seats_total": 12,
                    "title": "General admission updated"
                },
                {
                    "event_ticket_type_id": "%s",
                    "active": true,
                    "description": "Workshop access",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 1500,
                            "event_ticket_price_window_id": "%s"
                        }
                    ],
                    "seats_total": 8,
                    "title": "Workshop pass"
                }
            ]'::jsonb
        )$$,
        :'eventID',
        :'ticketType1ID',
        :'window1CurrentID',
        :'ticketType3ID',
        :'window3ID'
    ),
    'Should upsert payload ticket types and remove omitted ticket types'
);

-- Should update existing ticket types and remove omitted price windows
select is(
    (
        select jsonb_build_object(
            'active', active,
            'description', description,
            'order', "order",
            'seats_total', seats_total,
            'title', title
        )
        from event_ticket_type
        where event_ticket_type_id = :'ticketType1ID'::uuid
    ),
    jsonb_build_object(
        'active', false,
        'description', 'Updated general admission',
        'order', 1,
        'seats_total', 12,
        'title', 'General admission updated'
    ),
    'Should update existing ticket types and remove omitted price windows'
);

-- Should insert new ticket types from the payload
select is(
    (
        select jsonb_build_object(
            'description', description,
            'order', "order",
            'seats_total', seats_total,
            'title', title
        )
        from event_ticket_type
        where event_ticket_type_id = :'ticketType3ID'::uuid
    ),
    jsonb_build_object(
        'description', 'Workshop access',
        'order', 2,
        'seats_total', 8,
        'title', 'Workshop pass'
    ),
    'Should insert new ticket types from the payload'
);

-- Should remove ticket types omitted from the payload
select is(
    (select count(*) from event_ticket_type where event_ticket_type_id = :'ticketType2ID'::uuid),
    0::bigint,
    'Should remove ticket types omitted from the payload'
);

-- Should remove price windows omitted from the payload
select is(
    (select count(*) from event_ticket_price_window where event_ticket_price_window_id = :'window1OldID'::uuid),
    0::bigint,
    'Should remove price windows omitted from the payload'
);

-- Should reject updating a ticket type that belongs to another event
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"event_ticket_type_id": "%s", "order": 1, "price_windows": [{"amount_minor": 1000, "event_ticket_price_window_id": "%s"}], "seats_total": 1, "title": "Invalid"}]'::jsonb
        )$$,
        :'eventID',
        :'ticketTypeProtectedID',
        :'windowProtectedID'
    ),
    'ticket type does not belong to event',
    'Should reject updating a ticket type that belongs to another event'
);

-- Should reject updating a price window that belongs to another event
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"event_ticket_type_id": "%s", "order": 1, "price_windows": [{"amount_minor": 1000, "event_ticket_price_window_id": "%s"}], "seats_total": 1, "title": "Invalid"}]'::jsonb
        )$$,
        :'eventID',
        :'ticketType1ID',
        :'windowProtectedID'
    ),
    'ticket price window does not belong to event',
    'Should reject updating a price window that belongs to another event'
);

-- Should reject removing ticket types with purchases
select throws_ok(
    format(
        $$select sync_event_ticket_types('%s'::uuid, '[]'::jsonb)$$,
        :'eventProtectedID'
    ),
    'ticket types with purchases cannot be removed; deactivate them instead',
    'Should reject removing ticket types with purchases'
);

-- Should reject seat totals below current purchased inventory
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"event_ticket_type_id": "%s", "order": 1, "price_windows": [{"amount_minor": 3000, "event_ticket_price_window_id": "%s"}], "seats_total": 0, "title": "Protected pass"}]'::jsonb
        )$$,
        :'eventProtectedID',
        :'ticketTypeProtectedID',
        :'windowProtectedID'
    ),
    'ticket type seats_total (0) cannot be less than current number of purchased seats (1)',
    'Should reject seat totals below current purchased inventory'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
