-- Tests listing current and upcoming events for group check-in scanners.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '3a2c0000-0000-0000-0000-000000000009'
\set communityID '3a2c0000-0000-0000-0000-000000000001'
\set currentEventID '3a2c0000-0000-0000-0000-000000000002'
\set endedEventID '3a2c0000-0000-0000-0000-000000000008'
\set eventCategoryID '3a2c0000-0000-0000-0000-000000000003'
\set futureEventID '3a2c0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a2c0000-0000-0000-0000-000000000005'
\set groupID '3a2c0000-0000-0000-0000-000000000006'
\set pastEventID '3a2c0000-0000-0000-0000-000000000007'
\set unpublishedEventID '3a2c0000-0000-0000-0000-000000000010'
\set unscheduledEventID '3a2c0000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Current, future, explicitly ended, and expired events used by visibility scenarios
select fx_event(:'currentEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 hour',
    'published', true,
    'published_at', current_timestamp - interval '2 hours',
    'starts_at', current_timestamp - interval '1 hour'
));
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', date_trunc('day', current_timestamp at time zone 'UTC') at time zone 'UTC',
    'published', true,
    'published_at', current_timestamp - interval '1 day',
    'starts_at', (
                    date_trunc('day', current_timestamp at time zone 'UTC') - interval '1 hour'
                ) at time zone 'UTC'
));
select fx_event(:'futureEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'pastEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'published_at', current_timestamp - interval '4 days',
    'starts_at', current_timestamp - interval '3 days'
));

-- Canceled, unpublished, and unscheduled events excluded from the scanner
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '2 days'
));
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('starts_at', current_timestamp + interval '2 days'));
select fx_event(:'unscheduledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', current_timestamp
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list in-progress events before upcoming events
select results_eq(
    format(
        $$
            select value->>'event_id'
            from json_array_elements(list_group_check_in_events(%L::uuid)) value
        $$,
        :'groupID'
    ),
    format(
        $$ values (%L::text), (%L::text) $$,
        :'currentEventID',
        :'futureEventID'
    ),
    'Should list in-progress events before upcoming events'
);

-- Should return only narrow scanner fields
select ok(
    not list_group_check_in_events(:'groupID'::uuid)::text like '%check_in_code%',
    'Should return only narrow scanner fields'
);

-- Should return the exact scanner card contract
select results_eq(
    format(
        $$
            select key
            from json_each((list_group_check_in_events(%L::uuid)->0))
            order by key
        $$,
        :'groupID'
    ),
    $$
        values
            ('event_id'),
            ('in_progress'),
            ('kind'),
            ('location'),
            ('logo_url'),
            ('name'),
            ('starts_at'),
            ('timezone')
    $$,
    'Should return the exact scanner card contract'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
