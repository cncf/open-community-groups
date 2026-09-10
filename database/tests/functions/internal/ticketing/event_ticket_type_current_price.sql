-- Tests resolving the price window currently open for a ticket type.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set closedTicketTypeID 'f2080000-0000-0000-0000-000000000001'
\set communityID 'f2080000-0000-0000-0000-000000000002'
\set earlyWindowID 'f2080000-0000-0000-0000-000000000003'
\set eventCategoryID 'f2080000-0000-0000-0000-000000000004'
\set eventID 'f2080000-0000-0000-0000-000000000005'
\set expiredWindowID 'f2080000-0000-0000-0000-000000000006'
\set futureWindowID 'f2080000-0000-0000-0000-000000000007'
\set groupCategoryID 'f2080000-0000-0000-0000-000000000008'
\set groupID 'f2080000-0000-0000-0000-000000000009'
\set openEndedWindowID 'f2080000-0000-0000-0000-00000000000a'
\set openEndedTicketTypeID 'f2080000-0000-0000-0000-00000000000b'
\set regularWindowID 'f2080000-0000-0000-0000-00000000000c'
\set tieredTicketTypeID 'f2080000-0000-0000-0000-00000000000d'
\set unpricedTicketTypeID 'f2080000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group, event and ticket types
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_event_ticket_type(:'tieredTicketTypeID', :'eventID');
select fx_event_ticket_type(:'openEndedTicketTypeID', :'eventID');
select fx_event_ticket_type(:'closedTicketTypeID', :'eventID');
select fx_event_ticket_type(:'unpricedTicketTypeID', :'eventID');

-- Tiered pricing: an early window that already started, a regular window that
-- started later, and a future window
select fx_event_ticket_price_window(:'earlyWindowID', :'tieredTicketTypeID', jsonb_build_object(
    'amount_minor', 1000,
    'starts_at', current_timestamp - interval '3 days'
));
select fx_event_ticket_price_window(:'regularWindowID', :'tieredTicketTypeID', jsonb_build_object(
    'amount_minor', 2000,
    'starts_at', current_timestamp - interval '1 day'
));
select fx_event_ticket_price_window(:'futureWindowID', :'tieredTicketTypeID', jsonb_build_object(
    'amount_minor', 3000,
    'starts_at', current_timestamp + interval '1 day'
));

-- Window without dates
select fx_event_ticket_price_window(:'openEndedWindowID', :'openEndedTicketTypeID', jsonb_build_object(
    'amount_minor', 500
));

-- Window that already closed
select fx_event_ticket_price_window(:'expiredWindowID', :'closedTicketTypeID', jsonb_build_object(
    'amount_minor', 700,
    'ends_at', current_timestamp - interval '1 hour',
    'starts_at', current_timestamp - interval '2 days'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should pick the open window that started most recently
select is(
    event_ticket_type_current_price(:'tieredTicketTypeID'),
    2000::bigint,
    'Should pick the open window that started most recently'
);

-- Should treat windows without dates as always open
select is(
    event_ticket_type_current_price(:'openEndedTicketTypeID'),
    500::bigint,
    'Should treat windows without dates as always open'
);

-- Should return null when every window is closed
select is(
    event_ticket_type_current_price(:'closedTicketTypeID'),
    null::bigint,
    'Should return null when every window is closed'
);

-- Should return null for ticket types without windows
select is(
    event_ticket_type_current_price(:'unpricedTicketTypeID'),
    null::bigint,
    'Should return null for ticket types without windows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
