-- Tests guarded deletion for recurring event series.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'd1020000-0000-0000-0000-000000000001'
\set cohostGroupID 'd1020000-0000-0000-0000-000000000012'
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

-- Group co-hosting the eligible occurrences
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');

-- Actor deleting the recurring events
select fx_user(:'actorID', jsonb_build_object('username', 'actor-delete-event-series-events'));

-- Series containing two eligible unused drafts
select fx_event_series(:'eligibleSeriesID', :'groupID');

-- Series containing an eligible occurrence followed by a blocked occurrence
select fx_event_series(:'guardedSeriesID', :'groupID');

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

-- Approved co-host rows on every eligible occurrence
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    ('2025-01-01 00:00:00+00', 'approved', :'eligibleEventOneID', :'cohostGroupID'),
    ('2025-01-02 00:00:00+00', 'approved', :'eligibleEventTwoID', :'cohostGroupID');

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

-- Should delete an eligible draft series
select lives_ok(
    format(
        'select delete_event_series_events(%L, %L, %L::uuid[])',
        :'actorID',
        :'groupID',
        array[:'eligibleEventOneID', :'eligibleEventTwoID']
    ),
    'Should delete an eligible draft series'
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
select results_eq(
    format(
        $$
        select event_id, event_cohost_status_id, approved_at
        from event_cohost
        where event_id in (%L::uuid, %L::uuid)
        order by event_id
        $$,
        :'eligibleEventOneID', :'eligibleEventTwoID'
    ),
    format(
        $$
            values
                (%L::uuid, 'event-deleted'::text, '2025-01-01 00:00:00+00'::timestamptz),
                (%L::uuid, 'event-deleted'::text, '2025-01-02 00:00:00+00'::timestamptz)
        $$,
        :'eligibleEventOneID', :'eligibleEventTwoID'
    ),
    'Should close co-host rows for every deleted occurrence while keeping approval evidence'
);
select results_eq(
    $$
        select actor_user_id, resource_id
        from audit_log
        where action = 'event_deleted'
        order by resource_id
    $$,
    format(
        $$ values (%L::uuid, %L::uuid), (%L::uuid, %L::uuid) $$,
        :'actorID', :'eligibleEventOneID',
        :'actorID', :'eligibleEventTwoID'
    ),
    'Should audit every deleted occurrence with the acting user'
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

-- Should reject a series containing a blocked occurrence
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
