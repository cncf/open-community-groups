-- Tests detecting paid-capable event ticket configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c140000-0000-0000-0000-000000000001'
\set eventCategoryID '0c140000-0000-0000-0000-000000000002'
\set eventFreeID '0c140000-0000-0000-0000-000000000003'
\set eventNoTicketsID '0c140000-0000-0000-0000-000000000004'
\set eventPaidID '0c140000-0000-0000-0000-000000000005'
\set freeTicketTypeID '0c140000-0000-0000-0000-000000000006'
\set freeWindowID '0c140000-0000-0000-0000-000000000007'
\set groupCategoryID '0c140000-0000-0000-0000-000000000008'
\set groupID '0c140000-0000-0000-0000-000000000009'
\set paidTicketTypeID '0c140000-0000-0000-0000-00000000000a'
\set paidWindowID '0c140000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for paid-capability scenarios
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
    'paid-capability-community',
    'Paid Capability Community',
    'Community for paid-capability tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category for paid-capability scenarios
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category for paid-capability scenarios
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group for paid-capability scenarios
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Paid Capability Group',
    'paid-capability-group'
);

-- Events without tickets, with free tickets, and with paid tickets
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
        :'eventFreeID',
        'Event with free tickets',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Free Ticket Event',
        'USD',
        'free-ticket-event',
        'UTC'
    ),
    (
        :'eventNoTicketsID',
        'Event without tickets',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'No Tickets Event',
        null,
        'no-tickets-event',
        'UTC'
    ),
    (
        :'eventPaidID',
        'Event with paid tickets',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Paid Ticket Event',
        'USD',
        'paid-ticket-event',
        'UTC'
    );

-- Free and inactive paid ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title
) values
    (:'freeTicketTypeID', true, :'eventFreeID', 1, 10, 'Free pass'),
    (:'paidTicketTypeID', false, :'eventPaidID', 1, 10, 'Future paid pass');

-- Zero and future positive price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id,
    starts_at
) values
    (:'freeWindowID', 0, :'freeTicketTypeID', null),
    (:'paidWindowID', 2500, :'paidTicketTypeID', current_timestamp + interval '30 days');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should detect positive prices on inactive tiers and future windows
select is(
    is_event_paid_capable(:'eventPaidID'::uuid),
    true,
    'Should detect positive prices on inactive tiers and future windows'
);

-- Should return false when every configured price is zero
select is(
    is_event_paid_capable(:'eventFreeID'::uuid),
    false,
    'Should return false when every configured price is zero'
);

-- Should return false when the event has no ticket types
select is(
    is_event_paid_capable(:'eventNoTicketsID'::uuid),
    false,
    'Should return false when the event has no ticket types'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
