-- Tests the requirement that every event keeps at least one ticket type.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab1a0000-0000-0000-0000-000000000001'
\set eventCategoryID 'ab1a0000-0000-0000-0000-000000000002'
\set eventID 'ab1a0000-0000-0000-0000-000000000003'
\set groupCategoryID 'ab1a0000-0000-0000-0000-000000000004'
\set groupID 'ab1a0000-0000-0000-0000-000000000005'
\set otherEventID 'ab1a0000-0000-0000-0000-000000000006'
\set otherTicketTypeID 'ab1a0000-0000-0000-0000-000000000007'
\set ticketTypeID 'ab1a0000-0000-0000-0000-000000000008'
\set tierlessEventID 'ab1a0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event with a single ticket tier
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
values (:'eventID', 'Event with one tier', :'eventCategoryID', 'virtual', :'groupID', 'One Tier Event', 'one-tier-event', 'UTC');

-- Event receiving a moved ticket tier
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
values (:'otherEventID', 'Event with a spare tier', :'eventCategoryID', 'virtual', :'groupID', 'Spare Tier Event', 'spare-tier-event', 'UTC');

-- Only ticket tier of the single-tier event
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Ticket tier of the event receiving a moved tier
select fx_event_ticket_type(:'otherTicketTypeID', :'otherEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Check the deferred ticket-ownership constraints after each statement
set constraints
    event_has_ticket_type_on_event,
    event_has_ticket_type_on_event_ticket_type
    immediate;

-- Should accept an event inserted together with its first ticket tier
select lives_ok(
    format(
        $$
            with tierless_event as (
                insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
                values (%L::uuid, 'Event inserted with a tier', %L::uuid, 'virtual', %L::uuid, 'Paired Tier Event', 'paired-tier-event', 'UTC')
            )
            insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
            values (gen_random_uuid(), %L::uuid, 1, 5, 'General admission')
        $$,
        :'tierlessEventID',
        :'eventCategoryID',
        :'groupID',
        :'tierlessEventID'
    ),
    'Should accept an event inserted together with its first ticket tier'
);

-- Should accept deleting an event along with its ticket tiers
select lives_ok(
    format($$delete from event where event_id = %L::uuid$$, :'tierlessEventID'),
    'Should accept deleting an event along with its ticket tiers'
);

-- Should reject deleting an event's last ticket tier
select throws_ok(
    format($$delete from event_ticket_type where event_ticket_type_id = %L::uuid$$, :'ticketTypeID'),
    'OCG01',
    'events require at least one ticket type',
    'Should reject deleting an event''s last ticket tier'
);

-- Should reject moving an event's last ticket tier to another event
select throws_ok(
    format(
        $$update event_ticket_type set event_id = %L::uuid where event_ticket_type_id = %L::uuid$$,
        :'otherEventID',
        :'ticketTypeID'
    ),
    'OCG01',
    'events require at least one ticket type',
    'Should reject moving an event''s last ticket tier to another event'
);

-- Should reject persisting an event without a ticket tier
select throws_ok(
    format(
        $$
            insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
            values (gen_random_uuid(), 'Event without a tier', %L::uuid, 'virtual', %L::uuid, 'Tierless Event', 'tierless-event', 'UTC')
        $$,
        :'eventCategoryID',
        :'groupID'
    ),
    'OCG01',
    'events require at least one ticket type',
    'Should reject persisting an event without a ticket tier'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
