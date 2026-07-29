-- Tests returning public full event information.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c160000-0000-0000-0000-000000000001'
\set eventCategoryID '0c160000-0000-0000-0000-000000000002'
\set eventID '0c160000-0000-0000-0000-000000000003'
\set eventPrivateID '0c160000-0000-0000-0000-00000000000a'
\set groupCategoryID '0c160000-0000-0000-0000-000000000004'
\set groupID '0c160000-0000-0000-0000-000000000005'
\set privateOnlyTicketTypeID '0c160000-0000-0000-0000-00000000000b'
\set privateOnlyWindowID '0c160000-0000-0000-0000-00000000000c'
\set privateTicketTypeID '0c160000-0000-0000-0000-000000000006'
\set privateWindowID '0c160000-0000-0000-0000-000000000007'
\set publicTicketTypeID '0c160000-0000-0000-0000-000000000008'
\set publicWindowID '0c160000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for public full event scenarios
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
    'public-event-community',
    'Public Event Community',
    'Community for public full event tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category for public full event scenarios
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category for public full event scenarios
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group for public full event scenarios
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Public Event Group',
    'public-event-group'
);

-- Events with mixed and fully invitation-only ticket inventory
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    timezone
) values
    (
        :'eventID',
        'Event for public full event tests',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Public Event',
        'USD',
        true,
        'public-event',
        'UTC'
    ),
    (
        :'eventPrivateID',
        'Fully private event for public full event tests',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Private Event',
        'USD',
        true,
        'private-event',
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
        :'eventID',
        2,
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
    ),
    (
        :'privateOnlyTicketTypeID',
        true,
        'invitation_only',
        :'eventPrivateID',
        1,
        5,
        'Private-only pass'
    );

-- Current prices for public and invitation-only ticket types
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'privateWindowID', 5000, :'privateTicketTypeID'),
    (:'privateOnlyWindowID', 5000, :'privateOnlyTicketTypeID'),
    (:'publicWindowID', 2500, :'publicTicketTypeID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should replace organizer ticket inventory with the public projection
select is(
    (get_public_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    )::jsonb)->'ticket_types',
    list_public_event_ticket_types(:'eventID'::uuid),
    'Should replace organizer ticket inventory with the public projection'
);

-- Should omit ticket type details for fully invitation-only events
select ok(
    not (
        get_public_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventPrivateID'::uuid
        )::jsonb ? 'ticket_types'
    ),
    'Should omit ticket type details for fully invitation-only events'
);

-- Should preserve ticketed enrollment state for fully invitation-only events
select is(
    (
        get_public_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventPrivateID'::uuid
        )::jsonb
    )->>'is_ticketed',
    'true',
    'Should preserve ticketed enrollment state for fully invitation-only events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
