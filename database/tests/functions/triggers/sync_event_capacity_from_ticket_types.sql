-- Tests event capacity synchronization from ticket type seats.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab1c0000-0000-0000-0000-000000000001'
\set eventCategoryID 'ab1c0000-0000-0000-0000-000000000002'
\set eventID 'ab1c0000-0000-0000-0000-000000000003'
\set groupCategoryID 'ab1c0000-0000-0000-0000-000000000004'
\set groupID 'ab1c0000-0000-0000-0000-000000000005'
\set otherEventID 'ab1c0000-0000-0000-0000-000000000006'
\set otherTicketTypeID 'ab1c0000-0000-0000-0000-000000000007'
\set secondTicketTypeID 'ab1c0000-0000-0000-0000-000000000008'
\set ticketTypeID 'ab1c0000-0000-0000-0000-000000000009'

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
    :'communityID',
    'capacity-sync-community',
    'Capacity Sync Community',
    'Community for capacity synchronization trigger tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category used by the events
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category used by the hosting group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Capacity Sync Group', 'capacity-sync-group');

-- Event whose capacity follows its ticket tiers
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
values (:'eventID', 'Event with synced capacity', :'eventCategoryID', 'virtual', :'groupID', 'Synced Event', 'synced-event', 'UTC');

-- Event receiving a moved ticket tier
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
values (:'otherEventID', 'Event receiving a tier', :'eventCategoryID', 'virtual', :'groupID', 'Receiving Event', 'receiving-event', 'UTC');

-- Ticket tier of the receiving event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'otherTicketTypeID', :'otherEventID', 1, 5, 'General admission');

-- First ticket tier of the synced event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'ticketTypeID', :'eventID', 1, 10, 'General admission');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set capacity from the seeded tiers
select is(
    (select capacity from event where event_id = :'eventID'),
    10,
    'Should set capacity from the seeded tiers'
);

-- Should add inserted tier seats to the event capacity
select lives_ok(
    format(
        $$
            insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
            values (%L::uuid, %L::uuid, 2, 15, 'VIP')
        $$,
        :'secondTicketTypeID',
        :'eventID'
    ),
    'Should add inserted tier seats to the event capacity'
);

select is(
    (select capacity from event where event_id = :'eventID'),
    25,
    'Should persist the summed capacity after inserting a tier'
);

-- Should recompute capacity after resizing a tier
select lives_ok(
    format($$update event_ticket_type set seats_total = 0 where event_ticket_type_id = %L::uuid$$, :'secondTicketTypeID'),
    'Should recompute capacity after resizing a tier'
);

select is(
    (select capacity from event where event_id = :'eventID'),
    10,
    'Should persist the summed capacity after resizing a tier'
);

-- Should recompute capacity on both events when a tier moves
select lives_ok(
    format(
        $$update event_ticket_type set event_id = %L::uuid, seats_total = 20 where event_ticket_type_id = %L::uuid$$,
        :'otherEventID',
        :'secondTicketTypeID'
    ),
    'Should recompute capacity on both events when a tier moves'
);

select is(
    (select capacity from event where event_id = :'eventID'),
    10,
    'Should remove moved tier seats from the source event capacity'
);

select is(
    (select capacity from event where event_id = :'otherEventID'),
    25,
    'Should add moved tier seats to the target event capacity'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
