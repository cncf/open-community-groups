-- Tests recording daily event view counters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '5e0c0000-0000-0000-0000-000000000002'
\set communityID '5e0c0000-0000-0000-0000-000000000003'
\set conflictEventID '5e0c0000-0000-0000-0000-000000000009'
\set duplicateEventID '5e0c0000-0000-0000-0000-00000000000a'
\set eventCategoryID '5e0c0000-0000-0000-0000-000000000004'
\set groupCategoryID '5e0c0000-0000-0000-0000-000000000005'
\set groupID '5e0c0000-0000-0000-0000-000000000006'
\set inactiveGroupEventID '5e0c0000-0000-0000-0000-00000000000b'
\set inactiveGroupID '5e0c0000-0000-0000-0000-00000000000c'
\set publishedEventID '5e0c0000-0000-0000-0000-000000000007'
\set unknownEventID '5e0c0000-0000-0000-0000-000000000008'
\set unpublishedEventID '5e0c0000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Inactive group whose events are not publicly visible
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false
));

-- Published event receiving its first counter
select fx_event(:'publishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '10 days'
));

-- Published canceled event that still records views
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp + interval '20 days'
));

-- Unpublished event whose views are ignored
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp + interval '30 days'
));

-- Published event with an existing counter for today
select fx_event(:'conflictEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '40 days'
));

-- Published event receiving duplicate entries in one batch
select fx_event(:'duplicateEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '50 days'
));

-- Published event in an inactive group whose views are ignored
select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '60 days'
));

-- Existing counter incremented by the conflict scenario
insert into event_views (event_id, day, total)
values (:'conflictEventID', current_date, 3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should aggregate duplicate entries for the same event and day
select lives_ok(
    format(
        $$
        select update_event_views(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, 1),
                jsonb_build_array(%L::text, current_date::text, 2)
            )
        )
        $$,
        :'duplicateEventID', :'duplicateEventID'
    ),
    'Should record duplicate view entries without error'
);
select is(
    (
        select total
        from event_views
        where event_id = :'duplicateEventID'
        and day = current_date
    ),
    3,
    'Should aggregate duplicate entries for the same event and day'
);

-- Should ignore views of events in inactive groups
select lives_ok(
    format(
        $$
        select update_event_views(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, 2)
            )
        )
        $$,
        :'inactiveGroupEventID'
    ),
    'Should record views for an event in an inactive group without error'
);
select is(
    (
        select count(*)
        from event_views
        where event_id = :'inactiveGroupEventID'
    ),
    0::bigint,
    'Should ignore views of events in inactive groups'
);

-- Should increment existing counters on conflict
select lives_ok(
    format(
        $$
        select update_event_views(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, 4)
            )
        )
        $$,
        :'conflictEventID'
    ),
    'Should record additional views for an existing counter without error'
);
select is(
    (
        select total
        from event_views
        where event_id = :'conflictEventID'
        and day = current_date
    ),
    7,
    'Should increment existing counters on conflict'
);

-- Should insert counters only for published events
select lives_ok(
    format(
        $$
        select update_event_views(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, 3),
                jsonb_build_array(%L::text, current_date::text, 5),
                jsonb_build_array(%L::text, current_date::text, 7),
                jsonb_build_array(%L::text, current_date::text, 8)
            )
        )
        $$,
        :'publishedEventID', :'canceledEventID', :'unpublishedEventID', :'unknownEventID'
    ),
    'Should record views for known and unknown events without error'
);
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'day', day::text,
                'event_id', event_id::text,
                'total', total
            )
            order by day, event_id
        )
        from event_views
        where event_id in (
            :'canceledEventID',
            :'publishedEventID',
            :'unknownEventID',
            :'unpublishedEventID'
        )
    ),
    jsonb_build_array(
        jsonb_build_object(
            'day', current_date::text,
            'event_id', :'canceledEventID',
            'total', 5
        ),
        jsonb_build_object(
            'day', current_date::text,
            'event_id', :'publishedEventID',
            'total', 3
        )
    ),
    'Should insert counters only for published events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
