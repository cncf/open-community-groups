-- Tests listing normalized public event ticket types.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c150000-0000-0000-0000-000000000001'
\set eventCategoryID '0c150000-0000-0000-0000-000000000002'
\set eventID '0c150000-0000-0000-0000-000000000003'
\set eventPrivateID '0c150000-0000-0000-0000-000000000004'
\set groupCategoryID '0c150000-0000-0000-0000-000000000005'
\set groupID '0c150000-0000-0000-0000-000000000006'
\set mixedPrivateTicketTypeID '0c150000-0000-0000-0000-00000000000b'
\set privateTicketTypeID '0c150000-0000-0000-0000-000000000007'
\set privateWindowID '0c150000-0000-0000-0000-000000000008'
\set publicTicketTypeID '0c150000-0000-0000-0000-000000000009'
\set publicWindowID '0c150000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for public ticket projection scenarios
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
    'public-ticket-community',
    'Public Ticket Community',
    'Community for public ticket projection tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category for public ticket projection scenarios
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category for public ticket projection scenarios
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group for public ticket projection scenarios
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Public Ticket Group',
    'public-ticket-group'
);

-- Events with mixed and fully private ticket inventories
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values
    (
        :'eventID',
        'Event with public and invitation-only tickets',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Mixed Ticket Event',
        'USD',
        'mixed-ticket-event',
        'UTC'
    ),
    (
        :'eventPrivateID',
        'Event with invitation-only tickets',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Private Ticket Event',
        'USD',
        'private-ticket-event',
        'UTC'
    );

-- Public and invitation-only ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    availability,
    event_id,
    "order",
    seats_total,
    title
) values
    (
        :'privateTicketTypeID',
        true,
        'invitation_only',
        :'eventPrivateID',
        1,
        5,
        'Private pass'
    ),
    (
        :'publicTicketTypeID',
        true,
        'public',
        :'eventID',
        1,
        10,
        'Public pass'
    );

-- Current prices for public and invitation-only ticket types
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'privateWindowID', 5000, :'privateTicketTypeID'),
    (:'publicWindowID', 2500, :'publicTicketTypeID');

-- Invitation-only ticket on the mixed event
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    availability,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'mixedPrivateTicketTypeID',
    true,
    'invitation_only',
    :'eventID',
    2,
    3,
    'Sponsor pass'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude invitation-only ticket types from mixed events
select is(
    list_public_event_ticket_types(:'eventID'::uuid),
    jsonb_build_array(
        jsonb_build_object(
            'active', true,
            'availability', 'public',
            'current_price', jsonb_build_object('amount_minor', 2500),
            'event_ticket_type_id', :'publicTicketTypeID'::uuid,
            'order', 1,
            'price_windows', jsonb_build_array(
                jsonb_build_object(
                    'amount_minor', 2500,
                    'event_ticket_price_window_id', :'publicWindowID'::uuid
                )
            ),
            'remaining_seats', 10,
            'seats_total', 10,
            'sold_out', false,
            'title', 'Public pass'
        )
    ),
    'Should exclude invitation-only ticket types from mixed events'
);

-- Should return null for fully invitation-only events
select ok(
    list_public_event_ticket_types(:'eventPrivateID'::uuid) is null,
    'Should return null for fully invitation-only events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
