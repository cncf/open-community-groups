-- Tests resolving the moment an event stops being current.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f2010000-0000-0000-0000-000000000001'
\set datelessEventID 'f2010000-0000-0000-0000-000000000002'
\set endedEventID 'f2010000-0000-0000-0000-000000000003'
\set eventCategoryID 'f2010000-0000-0000-0000-000000000004'
\set groupCategoryID 'f2010000-0000-0000-0000-000000000005'
\set groupID 'f2010000-0000-0000-0000-000000000006'
\set startOnlyEventID 'f2010000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event with both dates
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2024-01-01 12:00:00+00',
    'starts_at', '2024-01-01 10:00:00+00'
));

-- Event with a start only
select fx_event(:'startOnlyEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', '2024-02-01 10:00:00+00'
));

-- Event without dates
select fx_event(:'datelessEventID', :'groupID', :'eventCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the end date when configured
select is(
    (select event_effective_ends_at(e) from event e where e.event_id = :'endedEventID'),
    '2024-01-01 12:00:00+00'::timestamptz,
    'Should return the end date when configured'
);

-- Should fall back to the start date without an end date
select is(
    (select event_effective_ends_at(e) from event e where e.event_id = :'startOnlyEventID'),
    '2024-02-01 10:00:00+00'::timestamptz,
    'Should fall back to the start date without an end date'
);

-- Should return null for dateless events
select is(
    (select event_effective_ends_at(e) from event e where e.event_id = :'datelessEventID'),
    null::timestamptz,
    'Should return null for dateless events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
