-- Tests listing a community's upcoming events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0d050000-0000-0000-0000-000000000001'
\set event1ID '0d050000-0000-0000-0000-000000000002'
\set event2ID '0d050000-0000-0000-0000-000000000003'
\set event3ID '0d050000-0000-0000-0000-000000000004'
\set event4ID '0d050000-0000-0000-0000-000000000005'
\set event5ID '0d050000-0000-0000-0000-000000000006'
\set event6ID '0d050000-0000-0000-0000-000000000007'
\set event7ID '0d050000-0000-0000-0000-000000000008'
\set eventCategoryID '0d050000-0000-0000-0000-000000000009'
\set eventDeletedID '0d050000-0000-0000-0000-000000000014'
\set group1ID '0d050000-0000-0000-0000-000000000010'
\set group2ID '0d050000-0000-0000-0000-000000000011'
\set groupCategoryID '0d050000-0000-0000-0000-000000000012'
\set unknownCommunityID '0d050000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and categories for upcoming events
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group with location data used by upcoming event summaries
select fx_group(:'group1ID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'city', 'New York',
    'country_code', 'US',
    'country_name', 'United States',
    'state', 'NY'
));

-- Group without location data used by virtual upcoming events
select fx_group(:'group2ID', :'communityID', :'groupCategoryID', jsonb_build_object('logo_url', 'https://example.com/virtual-group-logo.png'));

-- Events covering upcoming filters and ordering
select fx_event(:'event1ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 year' + interval '2 hours',
    'published', true,
    'starts_at', now() - interval '1 year'
));
select fx_event(:'event2ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 month' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 month'
));
select fx_event(:'event3ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '3 months' + interval '2 hours',
    'event_kind_id', 'virtual',
    'starts_at', now() + interval '3 months'
));
select fx_event(:'event4ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '2 weeks' + interval '2 hours',
    'starts_at', now() + interval '2 weeks'
));
select fx_event(:'event5ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 month' + interval '1 day' + interval '2 hours',
    'published', true,
    'starts_at', now() + interval '1 month' + interval '1 day',
    'test_event', true
));
select fx_event(:'event7ID', :'group2ID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '3 months' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '3 months'
));

-- Future event tied with another event's start time
select fx_event(:'event6ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 month' + interval '4 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 month'
));

-- Deleted future event excluded from upcoming events
select fx_event(:'eventDeletedID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'ends_at', now() + interval '2 weeks' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', false,
    'starts_at', now() + interval '2 weeks'
));

-- Nine distant future hybrid events exceeding the upcoming events limit
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
)
select
    format('0d050000-0000-0000-0000-%s', lpad(n::text, 12, '0'))::uuid,
    'Distant future event',
    :'eventCategoryID',
    'hybrid',
    :'group1ID',
    'Distant Future Event ' || n,
    true,
    'distant-future-event-' || n,
    now() + interval '5 years' + n * interval '1 day',
    'UTC'
from generate_series(101, 109) n;

-- Approved co-host credit that must not duplicate community upcoming events
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id
) values (
    current_timestamp,
    'approved',
    :'event2ID',
    :'group2ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return published non-test future events
select is(
    get_community_upcoming_events(:'communityID'::uuid, array['in-person', 'virtual'])::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event6ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group2ID'::uuid, :'event7ID'::uuid)::jsonb
    ),
    'Should return published non-test future events'
);

-- Should return empty array for non-existing community
select is(
    get_community_upcoming_events(:'unknownCommunityID'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    '[]'::jsonb,
    'Should return empty array for non-existing community'
);

-- Should show a co-hosted event once under its owner
select is(
    (
        select count(*)::int
        from jsonb_array_elements(
            get_community_upcoming_events(
                :'communityID'::uuid,
                array['in-person', 'virtual', 'hybrid']
            )::jsonb
        ) event_item
        where event_item->>'event_id' = :'event2ID'
        and event_item->>'group_slug' = (select slug from "group" where group_id = :'group1ID'::uuid)
    ),
    1,
    'Should show a co-hosted event once under its owner'
);

-- Should return only the first eight upcoming events
select is(
    (
        select jsonb_agg(event_item->>'event_id')
        from jsonb_array_elements(get_community_upcoming_events(:'communityID'::uuid, array['hybrid'])::jsonb) event_item
    ),
    (
        select jsonb_agg(format('0d050000-0000-0000-0000-%s', lpad(n::text, 12, '0')) order by n)
        from generate_series(101, 108) n
    ),
    'Should return only the first eight upcoming events'
);

-- Should order tied future events by event ID
select is(
    (
        select jsonb_agg(event_item->>'event_id')
        from jsonb_array_elements(
            get_community_upcoming_events(:'communityID'::uuid, array['virtual'])::jsonb
        ) event_item
    ),
    jsonb_build_array(:'event2ID', :'event6ID', :'event7ID'),
    'Should order tied future events by event ID'
);

-- Should include virtual events for groups without location data
select ok(
    exists (
        select 1
        from jsonb_array_elements(
            get_community_upcoming_events(:'communityID'::uuid, array['virtual'])::jsonb
        ) event_item
        where event_item->>'event_id' = :'event7ID'
    ),
    'Should include virtual events for groups without location data'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
