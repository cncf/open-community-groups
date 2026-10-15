-- Tests recording UTM-attributed event page views.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set aggregatedEventID '5e0d0000-0000-0000-0000-000000000001'
\set communityID '5e0d0000-0000-0000-0000-000000000002'
\set draftEventID '5e0d0000-0000-0000-0000-000000000003'
\set eventCategoryID '5e0d0000-0000-0000-0000-000000000004'
\set existingCounterEventID '5e0d0000-0000-0000-0000-000000000005'
\set groupCategoryID '5e0d0000-0000-0000-0000-000000000006'
\set groupID '5e0d0000-0000-0000-0000-000000000007'
\set insertedEventID '5e0d0000-0000-0000-0000-000000000008'
\set unknownEventID '5e0d0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the viewed events
select fx_community(:'communityID');

-- Event category used by the viewed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the viewed events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the viewed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Published event receiving duplicate payload entries
select fx_event(:'aggregatedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '10 days'
));

-- Unpublished event whose views are ignored
select fx_event(:'draftEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp + interval '20 days'
));

-- Published event with an existing UTM counter
select fx_event(:'existingCounterEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '30 days'
));

-- Published event receiving new UTM counters
select fx_event(:'insertedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '40 days'
));

-- Existing UTM counter incremented on conflict
insert into event_views_utm (event_id, day, total, utm_campaign, utm_medium, utm_source)
values (:'existingCounterEventID', current_date, 4, 'launch', 'email', 'newsletter');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should aggregate duplicate entries for the same event, day and UTM parameters
select lives_ok(
    format(
        $$
        select update_event_views_utm(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, 'launch', 'social', 'mastodon', 1),
                jsonb_build_array(%L::text, current_date::text, 'launch', 'social', 'mastodon', 2)
            )
        )
        $$,
        :'aggregatedEventID', :'aggregatedEventID'
    ),
    'Should record duplicate UTM view entries without error'
);
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'day', day::text,
                'total', total,
                'utm_campaign', utm_campaign,
                'utm_medium', utm_medium,
                'utm_source', utm_source
            )
        )
        from event_views_utm
        where event_id = :'aggregatedEventID'
    ),
    jsonb_build_array(
        jsonb_build_object(
            'day', current_date::text,
            'total', 3,
            'utm_campaign', 'launch',
            'utm_medium', 'social',
            'utm_source', 'mastodon'
        )
    ),
    'Should aggregate duplicate entries for the same event, day and UTM parameters'
);

-- Should ignore counters for unknown and unpublished events
select lives_ok(
    format(
        $$
        select update_event_views_utm(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, '', '', 'newsletter', 2),
                jsonb_build_array(%L::text, current_date::text, '', '', 'newsletter', 3)
            )
        )
        $$,
        :'draftEventID', :'unknownEventID'
    ),
    'Should record UTM views for unknown and unpublished events without error'
);
select is(
    (
        select count(*)
        from event_views_utm
        where event_id in (:'draftEventID', :'unknownEventID')
    ),
    0::bigint,
    'Should ignore counters for unknown and unpublished events'
);

-- Should increment existing counters on conflict
select lives_ok(
    format(
        $$
        select update_event_views_utm(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, 'launch', 'email', 'newsletter', 5)
            )
        )
        $$,
        :'existingCounterEventID'
    ),
    'Should record additional UTM views for an existing counter without error'
);
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'day', day::text,
                'total', total,
                'utm_campaign', utm_campaign,
                'utm_medium', utm_medium,
                'utm_source', utm_source
            )
        )
        from event_views_utm
        where event_id = :'existingCounterEventID'
    ),
    jsonb_build_array(
        jsonb_build_object(
            'day', current_date::text,
            'total', 9,
            'utm_campaign', 'launch',
            'utm_medium', 'email',
            'utm_source', 'newsletter'
        )
    ),
    'Should increment existing counters on conflict'
);

-- Should insert one counter per UTM parameters combination
select lives_ok(
    format(
        $$
        select update_event_views_utm(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, '', '', 'newsletter', 2),
                jsonb_build_array(%L::text, current_date::text, 'launch', 'email', 'newsletter', 6)
            )
        )
        $$,
        :'insertedEventID', :'insertedEventID'
    ),
    'Should record UTM views for new counters without error'
);
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'day', day::text,
                'total', total,
                'utm_campaign', utm_campaign,
                'utm_medium', utm_medium,
                'utm_source', utm_source
            )
            order by utm_campaign, utm_medium
        )
        from event_views_utm
        where event_id = :'insertedEventID'
    ),
    jsonb_build_array(
        jsonb_build_object(
            'day', current_date::text,
            'total', 2,
            'utm_campaign', '',
            'utm_medium', '',
            'utm_source', 'newsletter'
        ),
        jsonb_build_object(
            'day', current_date::text,
            'total', 6,
            'utm_campaign', 'launch',
            'utm_medium', 'email',
            'utm_source', 'newsletter'
        )
    ),
    'Should insert one counter per UTM parameters combination'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
