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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'views-community',
    'Views Community',
    'Community for update_event_views tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Views Group',
    'views-group',
    true,
    false
);

-- Event category and events
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Event whose views are updated by the test scenarios
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    published,
    canceled,
    deleted,
    starts_at
) values
    (
        :'publishedEventID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Published Event',
        'published-event',
        'Published event',
        'UTC',
        true,
        false,
        false,
        current_timestamp + interval '10 days'
    ),
    (
        :'canceledEventID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Canceled Event',
        'canceled-event',
        'Canceled event',
        'UTC',
        true,
        true,
        false,
        current_timestamp + interval '20 days'
    ),
    (
        :'canceledDraftEventID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Canceled Draft Event',
        'canceled-draft-event',
        'Canceled draft event',
        'UTC',
        false,
        true,
        false,
        current_timestamp + interval '30 days'
    );

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
