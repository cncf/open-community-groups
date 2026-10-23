-- Tests resolving the amount currently charged for a ticket type.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f2080000-0000-0000-0000-000000000002'
\set eventCategoryID 'f2080000-0000-0000-0000-000000000004'
\set eventID 'f2080000-0000-0000-0000-000000000005'
\set futureWindowID 'f2080000-0000-0000-0000-000000000007'
\set groupCategoryID 'f2080000-0000-0000-0000-000000000008'
\set groupID 'f2080000-0000-0000-0000-000000000009'
\set regularWindowID 'f2080000-0000-0000-0000-00000000000c'
\set tieredTicketTypeID 'f2080000-0000-0000-0000-00000000000d'
\set unpricedTicketTypeID 'f2080000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the ticketed event
select fx_community(:'communityID');

-- Event category for the ticketed event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category for the organizing group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group organizing the ticketed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning both ticket types
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Ticket type with an open window and a future window
select fx_event_ticket_type(:'tieredTicketTypeID', :'eventID');

-- Ticket type without price windows
select fx_event_ticket_type(:'unpricedTicketTypeID', :'eventID');

-- Future window that has not started yet
select fx_event_ticket_price_window(:'futureWindowID', :'tieredTicketTypeID', jsonb_build_object(
    'amount_minor', 3000,
    'starts_at', current_timestamp + interval '1 day'
));

-- Regular window that is currently open
select fx_event_ticket_price_window(:'regularWindowID', :'tieredTicketTypeID', jsonb_build_object(
    'amount_minor', 2000,
    'starts_at', current_timestamp - interval '1 day'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the amount of the current price window
select is(
    event_ticket_type_current_price(:'tieredTicketTypeID'),
    2000::bigint,
    'Should return the amount of the current price window'
);

-- Should return null for ticket types without an open window
select is(
    event_ticket_type_current_price(:'unpricedTicketTypeID'),
    null::bigint,
    'Should return null for ticket types without an open window'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
