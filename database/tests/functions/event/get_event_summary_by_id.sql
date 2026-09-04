-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '5e070000-0000-0000-0000-000000000001'
\set communityID '5e070000-0000-0000-0000-000000000002'
\set eventCategoryID '5e070000-0000-0000-0000-000000000003'
\set eventID '5e070000-0000-0000-0000-000000000004'
\set groupCategoryID '5e070000-0000-0000-0000-000000000005'
\set groupID '5e070000-0000-0000-0000-000000000006'
\set nonExistingEventID '5e070000-0000-0000-0000-000000000007'
\set ticketPriceWindowID '5e070000-0000-0000-0000-000000000008'
\set ticketTypeID '5e070000-0000-0000-0000-000000000009'
\set userID '5e070000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, event categories and users
select fx_community(:'communityID');
select fx_community(:'community2ID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');

-- Group category with scenario-specific state
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('created_at', '2025-01-01 00:00:00'));

-- Group with scenario-specific state
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('group_site_layout_id', 'default'));

-- Event with scenario-specific state
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 50,
    'event_kind_id', 'hybrid',
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', '2025-06-01 00:00:00+00',
    'starts_at', '2025-07-01 10:00:00+00',
    'timezone', 'America/New_York',
    'venue_city', 'Metropolis'
));

-- Event ticket type with scenario-specific state
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('seats_total', 50));

-- Event ticket price window with scenario-specific state
select fx_event_ticket_price_window(:'ticketPriceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));

-- Event attendee
insert into event_attendee (event_id, user_id, checked_in, checked_in_at, created_at)
values (:'eventID', :'userID', true, '2025-06-02 00:00:00', '2025-06-02 00:00:00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the same payload as get_event_summary
select is(
    get_event_summary_by_id(:'communityID'::uuid, :'eventID'::uuid)::jsonb,
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
    'Should return the same payload as get_event_summary'
);

-- Should return null for missing event
select ok(
    get_event_summary_by_id(:'communityID'::uuid, :'nonExistingEventID'::uuid) is null,
    'Should return null when the event does not exist'
);

-- Should return null when community mismatches
select ok(
    get_event_summary_by_id(:'community2ID'::uuid, :'eventID'::uuid) is null,
    'Should return null when the event belongs to another community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
