-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000021'
\set eventNoTicketTypesID '00000000-0000-0000-0000-000000000022'
\set groupCategoryID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000041'
\set ticketTypeAlphaID '00000000-0000-0000-0000-000000000051'
\set ticketTypeWorkshopID '00000000-0000-0000-0000-000000000052'
\set user1ID '00000000-0000-0000-0000-000000000061'
\set user2ID '00000000-0000-0000-0000-000000000062'
\set user3ID '00000000-0000-0000-0000-000000000063'
\set user4ID '00000000-0000-0000-0000-000000000064'
\set windowAlphaCurrentID '00000000-0000-0000-0000-000000000071'
\set windowAlphaExpiredID '00000000-0000-0000-0000-000000000072'
\set windowAlphaFutureID '00000000-0000-0000-0000-000000000073'
\set windowWorkshopID '00000000-0000-0000-0000-000000000074'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'communityID', 'community', 'Community', 'd', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'groupCategoryID', 'G1', 'g1');

-- Event category
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Meetup');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified) values
    (:'user1ID', 'test_hash', 'user1@example.test', 'user1', true),
    (:'user2ID', 'test_hash', 'user2@example.test', 'user2', true),
    (:'user3ID', 'test_hash', 'user3@example.test', 'user3', true),
    (:'user4ID', 'test_hash', 'user4@example.test', 'user4', true);

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published
) values
    (:'eventID', :'groupID', 'Event with ticket types', 'event-with-ticket-types', 'd', 'UTC', :'eventCategoryID', 'virtual', true),
    (:'eventNoTicketTypesID', :'groupID', 'Event without ticket types', 'event-without-ticket-types', 'd', 'UTC', :'eventCategoryID', 'virtual', true);

-- Event ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values
    (:'ticketTypeAlphaID', :'eventID', 1, 3, 'Alpha pass');

insert into event_ticket_type (
    event_ticket_type_id,
    description,
    event_id,
    "order",
    seats_total,
    title
) values
    (:'ticketTypeWorkshopID', 'Workshop access', :'eventID', 2, 5, 'Workshop pass');

-- Event ticket price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    ends_at,
    event_ticket_type_id,
    starts_at
) values
    (
        :'windowAlphaExpiredID',
        3000,
        current_timestamp - interval '2 days',
        :'ticketTypeAlphaID',
        null
    ),
    (
        :'windowAlphaCurrentID',
        2500,
        current_timestamp + interval '1 day',
        :'ticketTypeAlphaID',
        current_timestamp - interval '1 day'
    ),
    (
        :'windowAlphaFutureID',
        3500,
        null,
        :'ticketTypeAlphaID',
        current_timestamp + interval '2 days'
    ),
    (
        :'windowWorkshopID',
        1500,
        null,
        :'ticketTypeWorkshopID',
        null
    );

-- Event purchases
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (2500, 'USD', :'eventID', :'ticketTypeAlphaID', null, 'completed', 'Alpha pass', :'user1ID'),
    (2500, 'USD', :'eventID', :'ticketTypeAlphaID', current_timestamp + interval '1 hour', 'pending', 'Alpha pass', :'user2ID'),
    (2500, 'USD', :'eventID', :'ticketTypeAlphaID', current_timestamp - interval '1 hour', 'pending', 'Alpha pass', :'user3ID'),
    (2500, 'USD', :'eventID', :'ticketTypeAlphaID', null, 'refund-requested', 'Alpha pass', :'user4ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list ticket types with normalized prices and inventory
select is(
    list_event_ticket_types(:'eventID'::uuid),
    jsonb_build_array(
        jsonb_build_object(
            'active', true,
            'current_price', jsonb_build_object(
                'amount_minor', 2500,
                'ends_at', current_timestamp + interval '1 day',
                'starts_at', current_timestamp - interval '1 day'
            ),
            'event_ticket_type_id', :'ticketTypeAlphaID'::uuid,
            'order', 1,
            'price_windows', jsonb_build_array(
                jsonb_build_object(
                    'amount_minor', 3000,
                    'ends_at', current_timestamp - interval '2 days',
                    'event_ticket_price_window_id', :'windowAlphaExpiredID'::uuid
                ),
                jsonb_build_object(
                    'amount_minor', 2500,
                    'ends_at', current_timestamp + interval '1 day',
                    'event_ticket_price_window_id', :'windowAlphaCurrentID'::uuid,
                    'starts_at', current_timestamp - interval '1 day'
                ),
                jsonb_build_object(
                    'amount_minor', 3500,
                    'event_ticket_price_window_id', :'windowAlphaFutureID'::uuid,
                    'starts_at', current_timestamp + interval '2 days'
                )
            ),
            'remaining_seats', 0,
            'seats_total', 3,
            'sold_out', true,
            'title', 'Alpha pass'
        ),
        jsonb_build_object(
            'active', true,
            'current_price', jsonb_build_object(
                'amount_minor', 1500
            ),
            'description', 'Workshop access',
            'event_ticket_type_id', :'ticketTypeWorkshopID'::uuid,
            'order', 2,
            'price_windows', jsonb_build_array(
                jsonb_build_object(
                    'amount_minor', 1500,
                    'event_ticket_price_window_id', :'windowWorkshopID'::uuid
                )
            ),
            'remaining_seats', 5,
            'seats_total', 5,
            'sold_out', false,
            'title', 'Workshop pass'
        )
    ),
    'Should list ticket types with normalized prices and inventory'
);

-- Should return null for events without ticket types
select ok(
    list_event_ticket_types(:'eventNoTicketTypesID'::uuid) is null,
    'Should return null for events without ticket types'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
