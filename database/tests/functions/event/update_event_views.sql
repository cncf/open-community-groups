-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledDraftEventID '5e0c0000-0000-0000-0000-000000000001'
\set canceledEventID '5e0c0000-0000-0000-0000-000000000002'
\set communityID '5e0c0000-0000-0000-0000-000000000003'
\set eventCategoryID '5e0c0000-0000-0000-0000-000000000004'
\set groupCategoryID '5e0c0000-0000-0000-0000-000000000005'
\set groupID '5e0c0000-0000-0000-0000-000000000006'
\set publishedEventID '5e0c0000-0000-0000-0000-000000000007'
\set unknownEventID '5e0c0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose views are updated by the test scenarios
select fx_event(:'publishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '10 days'
));
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp + interval '20 days'
));
select fx_event(:'canceledDraftEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'starts_at', current_timestamp + interval '30 days'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should insert counters for published and canceled events
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
        :'publishedEventID', :'canceledEventID', :'canceledDraftEventID', :'unknownEventID'
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
    'Should insert counters for published and canceled events'
);

-- Should ignore counters for unknown events
select is(
    (select count(*) from event_views),
    2::bigint,
    'Should ignore counters for unknown events'
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
        :'publishedEventID'
    ),
    'Should record additional views for an existing counter without error'
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
            'total', 7
        )
    ),
    'Should increment existing counters on conflict'
);

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
        :'publishedEventID', :'publishedEventID'
    ),
    'Should record duplicate view entries without error'
);

select is(
    (
        select total
        from event_views
        where event_id = :'publishedEventID'
        and day = current_date
    ),
    10,
    'Should aggregate duplicate entries for the same event and day'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
