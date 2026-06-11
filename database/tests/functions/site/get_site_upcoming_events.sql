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
    'site-upcoming-events',
    'Site Upcoming Events',
    'Community used for site upcoming events tests',
    'https://example.com/site-upcoming-events-banner-mobile.png',
    'https://example.com/site-upcoming-events-banner.png',
    'https://example.com/site-upcoming-events-logo.png'
);

-- Inactive community
insert into community (
    community_id,
    name,
    display_name,
    description,
    active,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'community2ID',
    'inactive-site-upcoming-events',
    'Inactive Site Upcoming Events',
    'Inactive community used for site upcoming events tests',
    false,
    'https://example.com/inactive-site-upcoming-events-banner-mobile.png',
    'https://example.com/banner2.png',
    'https://example.com/logo2.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategory1ID', :'communityID', 'Technology'),
    (:'groupCategory2ID', :'community2ID', 'Technology');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    city,
    country_code,
    country_name,
    logo_url,
    state
) values (
    :'group1ID',
    :'communityID',
    :'groupCategory1ID',
    'Test Group',
    'test-group',
    'New York',
    'US',
    'United States',
    'https://example.com/group-logo.png',
    'NY'
);

insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    logo_url
) values (
    :'group2ID',
    :'communityID',
    :'groupCategory1ID',
    'Virtual Group',
    'virtual-group',
    'https://example.com/virtual-group-logo.png'
);

insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    logo_url
) values (
    :'group3ID',
    :'community2ID',
    :'groupCategory2ID',
    'Inactive Community Group',
    'inactive-community-group',
    'https://example.com/inactive-community-group-logo.png'
);

-- Event category
insert into event_category (event_category_id, community_id, name)
values
    (:'eventCategory1ID', :'communityID', 'Tech Talks'),
    (:'eventCategory2ID', :'community2ID', 'Tech Talks');

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    test_event,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at,
    canceled,
    logo_url
) values
    -- Past event
    (:'event1ID', 'Past Event', 'past-event', 'A past event', false, 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     now() - interval '1 year', now() - interval '1 year' + interval '2 hours', false, null),
    -- Future event 1 (with logo)
    (:'event2ID', 'Future Event 1', 'future-event-1', 'A future event', false, 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     now() + interval '1 month', now() + interval '1 month' + interval '2 hours', false,
     'https://example.com/event-logo.png'),
    -- Future event 2 (unpublished)
    (:'event3ID', 'Future Event 2', 'future-event-2', 'An unpublished event', false, 'UTC',
     :'eventCategory1ID', 'hybrid', :'group1ID', false,
     now() + interval '3 months', now() + interval '3 months' + interval '2 hours', false, null),
    -- Future event 3 (canceled - should be filtered out)
    (:'event4ID', 'Canceled Future Event', 'canceled-future-event',
     'A canceled event', false, 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', false,
     now() + interval '2 weeks', now() + interval '2 weeks' + interval '2 hours', true, null),
    -- Future event 4 (uses group logo fallback)
    (:'event5ID', 'No Logo Event', 'no-logo-event', 'An event without logo', true, 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     now() + interval '1 month' + interval '1 day',
     now() + interval '1 month' + interval '1 day' + interval '2 hours',
     false, null),
    -- Future event 5 (virtual event for a group without location data)
    (:'event7ID', 'Locationless Virtual Event', 'locationless-virtual-event',
     'A virtual event for a group without location data', false, 'UTC',
     :'eventCategory1ID', 'virtual', :'group2ID', true,
     now() + interval '3 months', now() + interval '3 months' + interval '2 hours',
     false, 'https://example.com/locationless-virtual-event-logo.png'),
    -- Future event 6 (in inactive community - should be filtered out)
    (:'event8ID', 'Inactive Community Event', 'inactive-community-event',
     'A future event in an inactive community', false, 'UTC',
     :'eventCategory2ID', 'in-person', :'group3ID', true,
     now() + interval '1 week', now() + interval '1 week' + interval '2 hours',
     false, 'https://example.com/inactive-community-event-logo.png');

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
