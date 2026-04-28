-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledDraftEventID '00000000-0000-0000-0000-000000000303'
\set canceledEventID '00000000-0000-0000-0000-000000000302'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000201'
\set groupID '00000000-0000-0000-0000-000000000101'
\set publishedEventID '00000000-0000-0000-0000-000000000301'
\set unknownEventID '00000000-0000-0000-0000-999999999999'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'views-community',
    'Views Community',
    'Community for update_event_views tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values ('00000000-0000-0000-0000-000000000501', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values (
    :'groupID',
    :'communityID',
    '00000000-0000-0000-0000-000000000501',
    'Views Group',
    'views-group',
    true,
    false
);

-- Event category and events
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

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
    (:'publishedEventID', :'eventCategoryID', 'in-person', :'groupID', 'Published Event', 'published-event', 'Published event', 'UTC', true, false, false, current_timestamp + interval '10 days'),
    (:'canceledEventID', :'eventCategoryID', 'in-person', :'groupID', 'Canceled Event', 'canceled-event', 'Canceled event', 'UTC', true, true, false, current_timestamp + interval '20 days'),
    (:'canceledDraftEventID', :'eventCategoryID', 'in-person', :'groupID', 'Canceled Draft Event', 'canceled-draft-event', 'Canceled draft event', 'UTC', false, true, false, current_timestamp + interval '30 days');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should insert counters for published and canceled events
select update_event_views(
    jsonb_build_array(
        jsonb_build_array(:'publishedEventID'::text, current_date::text, 3),
        jsonb_build_array(:'canceledEventID'::text, current_date::text, 5),
        jsonb_build_array(:'canceledDraftEventID'::text, current_date::text, 7),
        jsonb_build_array(:'unknownEventID'::text, current_date::text, 8)
    )
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
            'event_id', :'publishedEventID',
            'total', 3
        ),
        jsonb_build_object(
            'day', current_date::text,
            'event_id', :'canceledEventID',
            'total', 5
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
select update_event_views(
    jsonb_build_array(
        jsonb_build_array(:'publishedEventID'::text, current_date::text, 4)
    )
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
            'event_id', :'publishedEventID',
            'total', 7
        ),
        jsonb_build_object(
            'day', current_date::text,
            'event_id', :'canceledEventID',
            'total', 5
        )
    ),
    'Should increment existing counters on conflict'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
