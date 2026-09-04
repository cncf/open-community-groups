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

-- Baseline community, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose capacity follows its ticket tiers
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- Event receiving a moved ticket tier
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

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
