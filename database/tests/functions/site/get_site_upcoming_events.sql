-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '9a060000-0000-0000-0000-000000000001'
\set communityID '9a060000-0000-0000-0000-000000000002'
\set event1ID '9a060000-0000-0000-0000-000000000003'
\set event2ID '9a060000-0000-0000-0000-000000000004'
\set event3ID '9a060000-0000-0000-0000-000000000005'
\set event4ID '9a060000-0000-0000-0000-000000000006'
\set event5ID '9a060000-0000-0000-0000-000000000007'
\set event6ID '9a060000-0000-0000-0000-000000000008'
\set event7ID '9a060000-0000-0000-0000-000000000009'
\set event8ID '9a060000-0000-0000-0000-000000000010'
\set eventCategory1ID '9a060000-0000-0000-0000-000000000011'
\set eventCategory2ID '9a060000-0000-0000-0000-000000000012'
\set group1ID '9a060000-0000-0000-0000-000000000013'
\set group2ID '9a060000-0000-0000-0000-000000000014'
\set group3ID '9a060000-0000-0000-0000-000000000015'
\set groupCategory1ID '9a060000-0000-0000-0000-000000000016'
\set groupCategory2ID '9a060000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline active community and categories for site upcoming events
select fx_community(:'communityID');
select fx_group_category(:'groupCategory1ID', :'communityID');
select fx_event_category(:'eventCategory1ID', :'communityID');

-- Inactive community whose events are excluded
select fx_community(:'community2ID', jsonb_build_object('active', false));
select fx_group_category(:'groupCategory2ID', :'community2ID');
select fx_event_category(:'eventCategory2ID', :'community2ID');

-- Group with location data used by upcoming event summaries
select fx_group(:'group1ID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'city', 'New York',
    'country_code', 'US',
    'country_name', 'United States',
    'state', 'NY'
));

-- Group without location data used by virtual upcoming events
select fx_group(:'group2ID', :'communityID', :'groupCategory1ID', jsonb_build_object('logo_url', 'https://example.com/virtual-group-logo.png'));

-- Group in an inactive community
select fx_group(:'group3ID', :'community2ID', :'groupCategory2ID', jsonb_build_object('logo_url', 'https://example.com/inactive-community-group-logo.png'));

-- Events covering upcoming filters, inactive communities and ordering
select fx_event(:'event1ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() - interval '1 year' + interval '2 hours',
    'published', true,
    'starts_at', now() - interval '1 year'
));
select fx_event(:'event2ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '1 month' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 month'
));
select fx_event(:'event3ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '3 months' + interval '2 hours',
    'event_kind_id', 'hybrid',
    'starts_at', now() + interval '3 months'
));
select fx_event(:'event4ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '2 weeks' + interval '2 hours',
    'starts_at', now() + interval '2 weeks'
));
select fx_event(:'event5ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '1 month' + interval '1 day' + interval '2 hours',
    'published', true,
    'starts_at', now() + interval '1 month' + interval '1 day',
    'test_event', true
));
select fx_event(:'event7ID', :'group2ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '3 months' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '3 months'
));
select fx_event(:'event8ID', :'group3ID', :'eventCategory2ID', jsonb_build_object(
    'ends_at', now() + interval '1 week' + interval '2 hours',
    'published', true,
    'starts_at', now() + interval '1 week'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return published non-test future events
select is(
    get_site_upcoming_events(array['in-person', 'virtual', 'hybrid'])::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group2ID'::uuid, :'event7ID'::uuid)::jsonb
    ),
    'Should return published non-test future events'
);

-- Should not include events from inactive communities
select ok(
    not exists (
        select 1
        from jsonb_array_elements(get_site_upcoming_events(array['in-person', 'virtual', 'hybrid'])::jsonb) event_item
        where event_item->>'event_id' = :'event8ID'
    ),
    'Should not include events from inactive communities'
);

-- Should return empty array when no events match the filter
select is(
    get_site_upcoming_events(array['in-person'])::jsonb,
    '[]'::jsonb,
    'Should return empty array when no events match the filter'
);

-- Intentional mid-test seed: creates a tied future event after baseline assertions.
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at,
    canceled,
    logo_url
) values (
    :'event6ID',
    'Future Event 5',
    'future-event-5',
    'A future event with a tied start time',
    'UTC',
    :'eventCategory1ID',
    'virtual',
    :'group1ID',
    true,
    now() + interval '1 month',
    now() + interval '1 month' + interval '4 hours',
    false,
    'https://example.com/event-5-logo.png'
);

-- Should order tied future events by event ID
select is(
    (
        select jsonb_agg(event_item->>'event_id')
        from jsonb_array_elements(get_site_upcoming_events(array['virtual'])::jsonb) event_item
    ),
    jsonb_build_array(:'event2ID', :'event6ID', :'event7ID'),
    'Should order tied future events by event ID'
);

-- Should include virtual events for groups without location data
select ok(
    exists (
        select 1
        from jsonb_array_elements(get_site_upcoming_events(array['virtual'])::jsonb) event_item
        where event_item->>'event_id' = :'event7ID'
    ),
    'Should include virtual events for groups without location data'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
