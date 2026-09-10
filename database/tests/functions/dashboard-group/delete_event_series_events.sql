-- Tests atomic guarded deletion for recurring event series.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'd1020000-0000-0000-0000-000000000001'
\set communityID 'd1020000-0000-0000-0000-000000000002'
\set eligibleEventOneID 'd1020000-0000-0000-0000-000000000003'
\set eligibleEventTwoID 'd1020000-0000-0000-0000-000000000004'
\set eligibleSeriesID 'd1020000-0000-0000-0000-000000000005'
\set eventCategoryID 'd1020000-0000-0000-0000-000000000006'
\set groupCategoryID 'd1020000-0000-0000-0000-000000000007'
\set groupID 'd1020000-0000-0000-0000-000000000008'
\set guardedAllowedEventID 'd1020000-0000-0000-0000-000000000009'
\set guardedBlockedEventID 'd1020000-0000-0000-0000-000000000010'
\set guardedSeriesID 'd1020000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================


-- Community owning both recurring series
select fx_community(:'communityID', jsonb_build_object('name', 'community-delete-event-series-events'));

-- Baseline categories
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category owning the test group
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Category'));

-- Group owning both recurring series
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('slug', 'group'));

-- Actor deleting the recurring events
select fx_user(:'actorID', jsonb_build_object('username', 'actor-delete-event-series-events'));

-- Series containing two eligible unused drafts
insert into event_series (
    created_by,
    event_series_id,
    group_id,
    recurrence_additional_occurrences,
    recurrence_anchor_starts_at,
    recurrence_pattern,
    timezone
) values (
    :'actorID',
    :'eligibleSeriesID',
    :'groupID',
    1,
    now() + interval '1 day',
    'weekly',
    'UTC'
);

-- Series containing an eligible occurrence followed by a blocked occurrence
insert into event_series (
    created_by,
    event_series_id,
    group_id,
    recurrence_additional_occurrences,
    recurrence_anchor_starts_at,
    recurrence_pattern,
    timezone
) values (
    :'actorID',
    :'guardedSeriesID',
    :'groupID',
    1,
    now() + interval '3 days',
    'weekly',
    'UTC'
);

-- Eligible unused draft occurrences
select fx_event(:'eligibleEventOneID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'One',
    'event_series_id', :'eligibleSeriesID',
    'name', 'One',
    'slug', 'one',
    'starts_at', now() + interval '1 day'
));
select fx_event(:'eligibleEventTwoID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Two',
    'event_series_id', :'eligibleSeriesID',
    'name', 'Two',
    'starts_at', now() + interval '2 days'
));

-- Guarded series whose first occurrence is already canceled
select fx_event(:'guardedAllowedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'description', 'Allowed',
    'event_series_id', :'guardedSeriesID',
    'name', 'Allowed',
    'starts_at', now() + interval '3 days'
));

-- Guarded series whose second occurrence must be canceled first
select fx_event(:'guardedBlockedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Blocked',
    'event_series_id', :'guardedSeriesID',
    'name', 'Blocked',
    'published', true,
    'slug', 'blocked',
    'starts_at', now() + interval '4 days'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete an eligible draft series atomically
select lives_ok(
    format(
        'select delete_event_series_events(%L, %L, %L::uuid[])',
        :'actorID',
        :'groupID',
        array[:'eligibleEventOneID', :'eligibleEventTwoID']
    ),
    'Should delete an eligible draft series atomically'
);
select is(
    (
        select count(*)::int
        from event
        where event_series_id = :'eligibleSeriesID'
        and deleted
    ),
    2,
    'Should delete every eligible occurrence'
);
select is(
    (
        select count(*)::int
        from event
        where event_series_id = :'eligibleSeriesID'
        and not published
    ),
    2,
    'Should unpublish every deleted occurrence'
);
select is(
    (select count(*)::int from audit_log where action = 'event_deleted'),
    2,
    'Should audit every deleted occurrence'
);

-- Should reject replaying deletion for inactive occurrences
select throws_ok(
    format(
        'select delete_event_series_events(%L, %L, %L::uuid[])',
        :'actorID',
        :'groupID',
        array[:'eligibleEventOneID', :'eligibleEventTwoID']
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject replaying deletion for inactive occurrences'
);

-- Should roll back every occurrence when one deletion is blocked
select throws_ok(
    format(
        'select delete_event_series_events(%L, %L, %L::uuid[])',
        :'actorID',
        :'groupID',
        array[:'guardedAllowedEventID', :'guardedBlockedEventID']
    ),
    'OCG01',
    'event must be canceled and all payment work settled before deletion',
    'Should reject a series containing a blocked occurrence'
);
select is(
    (
        select count(*)::int
        from event
        where event_series_id = :'guardedSeriesID'
        and deleted
    ),
    0,
    'Should roll back every occurrence when one deletion is blocked'
);
select is(
    (select count(*)::int from audit_log where action = 'event_deleted'),
    2,
    'Should roll back audit rows for a blocked series deletion'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
