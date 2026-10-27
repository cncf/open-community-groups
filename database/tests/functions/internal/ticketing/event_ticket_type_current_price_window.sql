-- Tests selecting the price window currently open for a ticket type.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c9e10000-0000-0000-0000-000000000001'
\set eventCategoryID 'c9e10000-0000-0000-0000-000000000002'
\set eventID 'c9e10000-0000-0000-0000-000000000003'
\set expiredTicketTypeID 'c9e10000-0000-0000-0000-000000000004'
\set expiredWindowID 'c9e10000-0000-0000-0000-000000000005'
\set futureTicketTypeID 'c9e10000-0000-0000-0000-000000000006'
\set futureWindowID 'c9e10000-0000-0000-0000-000000000007'
\set groupCategoryID 'c9e10000-0000-0000-0000-000000000008'
\set groupID 'c9e10000-0000-0000-0000-000000000009'
\set latestEarlyWindowID 'c9e10000-0000-0000-0000-00000000000a'
\set latestFutureWindowID 'c9e10000-0000-0000-0000-00000000000b'
\set latestRegularWindowID 'c9e10000-0000-0000-0000-00000000000c'
\set latestTicketTypeID 'c9e10000-0000-0000-0000-00000000000d'
\set nullStartDatedWindowID 'c9e10000-0000-0000-0000-00000000000e'
\set nullStartTicketTypeID 'c9e10000-0000-0000-0000-00000000000f'
\set nullStartUndatedWindowID 'c9e10000-0000-0000-0000-000000000010'
\set openEndedTicketTypeID 'c9e10000-0000-0000-0000-000000000011'
\set openEndedWindowID 'c9e10000-0000-0000-0000-000000000012'
\set tieFirstWindowID 'c9e10000-0000-0000-0000-000000000013'
\set tieSecondWindowID 'c9e10000-0000-0000-0000-000000000014'
\set tieTicketTypeID 'c9e10000-0000-0000-0000-000000000015'
\set unpricedTicketTypeID 'c9e10000-0000-0000-0000-000000000016'

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

-- Event owning every ticket type
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Ticket type whose only window already closed
select fx_event_ticket_type(:'expiredTicketTypeID', :'eventID');

-- Ticket type whose only window has not started yet
select fx_event_ticket_type(:'futureTicketTypeID', :'eventID');

-- Ticket type with two open windows that started at different times
select fx_event_ticket_type(:'latestTicketTypeID', :'eventID');

-- Ticket type with an open window without a start and a started dated one
select fx_event_ticket_type(:'nullStartTicketTypeID', :'eventID');

-- Ticket type whose only window has no dates
select fx_event_ticket_type(:'openEndedTicketTypeID', :'eventID');

-- Ticket type with two open windows that started at the same time
select fx_event_ticket_type(:'tieTicketTypeID', :'eventID');

-- Ticket type without price windows
select fx_event_ticket_type(:'unpricedTicketTypeID', :'eventID');

-- Window that already closed
select fx_event_ticket_price_window(:'expiredWindowID', :'expiredTicketTypeID', jsonb_build_object(
    'amount_minor', 700,
    'ends_at', current_timestamp - interval '1 hour',
    'starts_at', current_timestamp - interval '2 days'
));

-- Window that has not started yet
select fx_event_ticket_price_window(:'futureWindowID', :'futureTicketTypeID', jsonb_build_object(
    'amount_minor', 900,
    'starts_at', current_timestamp + interval '1 day'
));

-- Early window that is still open without an end
select fx_event_ticket_price_window(:'latestEarlyWindowID', :'latestTicketTypeID', jsonb_build_object(
    'amount_minor', 1000,
    'starts_at', current_timestamp - interval '3 days'
));

-- Future window that has not started yet
select fx_event_ticket_price_window(:'latestFutureWindowID', :'latestTicketTypeID', jsonb_build_object(
    'amount_minor', 3000,
    'starts_at', current_timestamp + interval '1 day'
));

-- Regular window that started after the early one and is still open
select fx_event_ticket_price_window(:'latestRegularWindowID', :'latestTicketTypeID', jsonb_build_object(
    'amount_minor', 2000,
    'ends_at', current_timestamp + interval '2 days',
    'starts_at', current_timestamp - interval '1 day'
));

-- Started dated window competing with a window without a start
select fx_event_ticket_price_window(:'nullStartDatedWindowID', :'nullStartTicketTypeID', jsonb_build_object(
    'amount_minor', 1200,
    'starts_at', current_timestamp - interval '1 day'
));

-- Open window without a start competing with a started dated one
select fx_event_ticket_price_window(:'nullStartUndatedWindowID', :'nullStartTicketTypeID', jsonb_build_object(
    'amount_minor', 1100,
    'ends_at', current_timestamp + interval '1 day'
));

-- Window without dates
select fx_event_ticket_price_window(:'openEndedWindowID', :'openEndedTicketTypeID', jsonb_build_object(
    'amount_minor', 500
));

-- Tied window with the lower identifier
select fx_event_ticket_price_window(:'tieFirstWindowID', :'tieTicketTypeID', jsonb_build_object(
    'amount_minor', 1300,
    'starts_at', '2020-01-01 00:00:00+00'::timestamptz
));

-- Tied window with the higher identifier
select fx_event_ticket_price_window(:'tieSecondWindowID', :'tieTicketTypeID', jsonb_build_object(
    'amount_minor', 1400,
    'starts_at', '2020-01-01 00:00:00+00'::timestamptz
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should break start ties by window identifier
select results_eq(
    format(
        $$select event_ticket_price_window_id from event_ticket_type_current_price_window(%L::uuid)$$,
        :'tieTicketTypeID'
    ),
    format($$values (%L::uuid)$$, :'tieFirstWindowID'),
    'Should break start ties by window identifier'
);

-- Should pick the open window that started most recently
select results_eq(
    format(
        $$
            select amount_minor, ends_at, event_ticket_price_window_id, starts_at
            from event_ticket_type_current_price_window(%L::uuid)
        $$,
        :'latestTicketTypeID'
    ),
    format(
        $$values (2000::bigint, current_timestamp + interval '2 days', %L::uuid, current_timestamp - interval '1 day')$$,
        :'latestRegularWindowID'
    ),
    'Should pick the open window that started most recently'
);

-- Should return no window for ticket types without windows
select is_empty(
    format(
        $$select * from event_ticket_type_current_price_window(%L::uuid)$$,
        :'unpricedTicketTypeID'
    ),
    'Should return no window for ticket types without windows'
);

-- Should return no window when every window already closed
select is_empty(
    format(
        $$select * from event_ticket_type_current_price_window(%L::uuid)$$,
        :'expiredTicketTypeID'
    ),
    'Should return no window when every window already closed'
);

-- Should return no window when every window starts in the future
select is_empty(
    format(
        $$select * from event_ticket_type_current_price_window(%L::uuid)$$,
        :'futureTicketTypeID'
    ),
    'Should return no window when every window starts in the future'
);

-- Should sort windows without a start after started dated windows
select results_eq(
    format(
        $$select event_ticket_price_window_id from event_ticket_type_current_price_window(%L::uuid)$$,
        :'nullStartTicketTypeID'
    ),
    format($$values (%L::uuid)$$, :'nullStartDatedWindowID'),
    'Should sort windows without a start after started dated windows'
);

-- Should treat windows without dates as always open
select results_eq(
    format(
        $$select event_ticket_price_window_id from event_ticket_type_current_price_window(%L::uuid)$$,
        :'openEndedTicketTypeID'
    ),
    format($$values (%L::uuid)$$, :'openEndedWindowID'),
    'Should treat windows without dates as always open'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
