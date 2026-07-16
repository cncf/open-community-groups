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
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.test/mobile.png',
    'https://example.test/banner.png',
    :'communityID',
    'Community',
    'Community',
    'https://example.test/logo.png',
    'cancelable-series-community'
);

-- Event category shared by the series events
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category shared by the series groups
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Groups used to verify ownership scoping
insert into "group" (community_id, group_category_id, group_id, name, slug) values
    (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group'),
    (:'communityID', :'groupCategoryID', :'otherGroupID', 'Other Group', 'other-group');

-- User who created both event series
insert into "user" (auth_hash, email, user_id, username)
values ('user', 'user@example.test', :'userID', 'user');

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
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone,

    canceled,
    deleted,
    deleted_at,
    ends_at,
    event_series_id
) values
    ('Canceled', :'eventCategoryID', :'canceledEventID', 'virtual', :'groupID', 'Canceled', true, 'canceled', now() + interval '15 days', 'UTC', true, false, null, now() + interval '15 days 1 hour', :'eventSeriesID'),
    ('Deleted', :'eventCategoryID', :'deletedEventID', 'virtual', :'groupID', 'Deleted', false, 'deleted', now() + interval '22 days', 'UTC', false, true, current_timestamp, now() + interval '22 days 1 hour', :'eventSeriesID'),
    ('First', :'eventCategoryID', :'firstEventID', 'virtual', :'groupID', 'First', true, 'first', now() + interval '1 day', 'UTC', false, false, null, now() + interval '1 day 1 hour', :'eventSeriesID'),
    ('Standalone', :'eventCategoryID', :'noSeriesEventID', 'virtual', :'groupID', 'Standalone', true, 'standalone', now() + interval '1 day', 'UTC', false, false, null, now() + interval '1 day 1 hour', null),
    ('Other', :'eventCategoryID', :'otherEventID', 'virtual', :'otherGroupID', 'Other', true, 'other', now() + interval '1 day', 'UTC', false, false, null, now() + interval '1 day 1 hour', :'otherSeriesID'),
    ('Past', :'eventCategoryID', :'pastEventID', 'virtual', :'groupID', 'Past', true, 'past', now() - interval '2 hours', 'UTC', false, false, null, now() - interval '1 hour', :'eventSeriesID'),
    ('Second', :'eventCategoryID', :'secondEventID', 'virtual', :'groupID', 'Second', true, 'second', now() + interval '8 days', 'UTC', false, false, null, now() + interval '8 days 1 hour', :'eventSeriesID');

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
