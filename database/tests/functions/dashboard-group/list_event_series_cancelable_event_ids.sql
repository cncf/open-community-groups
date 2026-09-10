-- Tests selection of cancelable active occurrences from an event series.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'd3020000-0000-0000-0000-000000000001'
\set communityID 'd3020000-0000-0000-0000-000000000002'
\set deletedEventID 'd3020000-0000-0000-0000-000000000003'
\set eventCategoryID 'd3020000-0000-0000-0000-000000000004'
\set eventSeriesID 'd3020000-0000-0000-0000-000000000005'
\set firstEventID 'd3020000-0000-0000-0000-000000000006'
\set groupCategoryID 'd3020000-0000-0000-0000-000000000007'
\set groupID 'd3020000-0000-0000-0000-000000000008'
\set missingEventID 'd3020000-0000-0000-0000-000000000009'
\set noSeriesEventID 'd3020000-0000-0000-0000-000000000010'
\set otherEventID 'd3020000-0000-0000-0000-000000000011'
\set otherGroupID 'd3020000-0000-0000-0000-000000000012'
\set otherSeriesID 'd3020000-0000-0000-0000-000000000013'
\set pastEventID 'd3020000-0000-0000-0000-000000000014'
\set secondEventID 'd3020000-0000-0000-0000-000000000015'
\set userID 'd3020000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning both series groups
select fx_community(:'communityID', jsonb_build_object(
    'description', 'Community',
    'display_name', 'Community'
));

-- Event category shared by the series events
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'Events'));

-- Group category shared by the series groups
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Groups'));

-- Baseline groups
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Groups used to verify ownership scoping
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Group',
    'slug', 'group'
));

-- User who created both event series
select fx_user(:'userID', jsonb_build_object(
    'auth_hash', 'user',
    'username', 'user-list-event-series-cancelable-event-ids'
));

-- Event series used for group and ownership scenarios
insert into event_series (
    event_series_id,
    group_id,
    recurrence_additional_occurrences,
    recurrence_anchor_starts_at,
    recurrence_pattern,
    timezone,

    created_by
) values
    (:'eventSeriesID', :'groupID', 4, now() + interval '1 day', 'weekly', 'UTC', :'userID'),
    (:'otherSeriesID', :'otherGroupID', 1, now() + interval '1 day', 'weekly', 'UTC', :'userID');

-- Events covering active, completed, canceled, deleted, standalone, and cross-group cases
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '15 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'published', true,
    'slug', 'canceled',
    'starts_at', now() + interval '15 days'
));
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', current_timestamp,
    'ends_at', now() + interval '22 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'slug', 'deleted',
    'starts_at', now() + interval '22 days'
));
select fx_event(:'firstEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'published', true,
    'slug', 'first',
    'starts_at', now() + interval '1 day'
));
select fx_event(:'noSeriesEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'slug', 'standalone',
    'starts_at', now() + interval '1 day'
));
select fx_event(:'otherEventID', :'otherGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'otherSeriesID',
    'published', true,
    'slug', 'other',
    'starts_at', now() + interval '1 day'
));
select fx_event(:'pastEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'published', true,
    'slug', 'past',
    'starts_at', now() - interval '2 hours'
));
select fx_event(:'secondEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '8 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'published', true,
    'slug', 'second',
    'starts_at', now() + interval '8 days'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude canceled, completed, and deleted occurrences
select is(
    list_event_series_cancelable_event_ids(:'groupID', :'pastEventID'),
    array[:'firstEventID'::uuid, :'secondEventID'::uuid],
    'Should exclude canceled, completed, and deleted occurrences'
);

-- Should return active occurrences in chronological order
select is(
    list_event_series_cancelable_event_ids(:'groupID', :'secondEventID'),
    array[:'firstEventID'::uuid, :'secondEventID'::uuid],
    'Should return active occurrences in chronological order'
);

-- Should return no occurrences for a deleted selected event
select is(
    list_event_series_cancelable_event_ids(:'groupID', :'deletedEventID'),
    '{}'::uuid[],
    'Should return no occurrences for a deleted selected event'
);

-- Should return no occurrences for a missing event
select is(
    list_event_series_cancelable_event_ids(:'groupID', :'missingEventID'),
    '{}'::uuid[],
    'Should return no occurrences for a missing event'
);

-- Should return no occurrences for a standalone event
select is(
    list_event_series_cancelable_event_ids(:'groupID', :'noSeriesEventID'),
    '{}'::uuid[],
    'Should return no occurrences for a standalone event'
);

-- Should return no occurrences when the selected event belongs to another group
select is(
    list_event_series_cancelable_event_ids(:'groupID', :'otherEventID'),
    '{}'::uuid[],
    'Should return no occurrences when the selected event belongs to another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
