-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '0d050000-0000-0000-0000-000000000001'
\set event1ID '0d050000-0000-0000-0000-000000000002'
\set event2ID '0d050000-0000-0000-0000-000000000003'
\set event3ID '0d050000-0000-0000-0000-000000000004'
\set event4ID '0d050000-0000-0000-0000-000000000005'
\set event5ID '0d050000-0000-0000-0000-000000000006'
\set event6ID '0d050000-0000-0000-0000-000000000007'
\set event7ID '0d050000-0000-0000-0000-000000000008'
\set eventCategoryID '0d050000-0000-0000-0000-000000000009'
\set group1ID '0d050000-0000-0000-0000-000000000010'
\set group2ID '0d050000-0000-0000-0000-000000000011'
\set groupCategoryID '0d050000-0000-0000-0000-000000000012'
\set unknownAllianceID '0d050000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'alliance-upcoming-events',
    'Alliance Upcoming Events',
    'Alliance used for upcoming events tests',
    'https://example.com/alliance-upcoming-events-banner-mobile.png',
    'https://example.com/alliance-upcoming-events-banner.png',
    'https://example.com/alliance-upcoming-events-logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Group
insert into "group" (
    group_id,
    alliance_id,
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
    :'allianceID',
    :'groupCategoryID',
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
    alliance_id,
    group_category_id,
    name,
    slug,
    logo_url
) values (
    :'group2ID',
    :'allianceID',
    :'groupCategoryID',
    'Virtual Group',
    'virtual-group',
    'https://example.com/virtual-group-logo.png'
);

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Tech Talks');

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
     :'eventCategoryID', 'in-person', :'group1ID', true,
     now() - interval '1 year', now() - interval '1 year' + interval '2 hours', false, null),
    -- Future event 1 (with logo)
    (:'event2ID', 'Future Event 1', 'future-event-1', 'A future event', false, 'UTC',
     :'eventCategoryID', 'virtual', :'group1ID', true,
     now() + interval '1 month', now() + interval '1 month' + interval '2 hours', false,
     'https://example.com/event-logo.png'),
    -- Future event 2 (unpublished)
    (:'event3ID', 'Future Event 2', 'future-event-2', 'An unpublished event', false, 'UTC',
     :'eventCategoryID', 'hybrid', :'group1ID', false,
     now() + interval '3 months', now() + interval '3 months' + interval '2 hours', false, null),
    -- Future event 3 (canceled - should be filtered out)
    (:'event4ID', 'Canceled Future Event', 'canceled-future-event',
     'A canceled event', false, 'UTC',
     :'eventCategoryID', 'in-person', :'group1ID', false,
     now() + interval '2 weeks', now() + interval '2 weeks' + interval '2 hours', true, null),
    -- Future event 4 (uses group logo fallback)
    (:'event5ID', 'No Logo Event', 'no-logo-event', 'An event without logo', true, 'UTC',
     :'eventCategoryID', 'in-person', :'group1ID', true,
     now() + interval '1 month' + interval '1 day',
     now() + interval '1 month' + interval '1 day' + interval '2 hours',
     false, null),
    -- Future event 5 (virtual event for a group without location data)
    (:'event7ID', 'Locationless Virtual Event', 'locationless-virtual-event',
     'A virtual event for a group without location data', false, 'UTC',
     :'eventCategoryID', 'virtual', :'group2ID', true,
     now() + interval '3 months', now() + interval '3 months' + interval '2 hours',
     false, 'https://example.com/locationless-virtual-event-logo.png');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return published non-test future events
select is(
    get_alliance_upcoming_events(:'allianceID'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    jsonb_build_array(
        get_event_summary(:'allianceID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'allianceID'::uuid, :'group2ID'::uuid, :'event7ID'::uuid)::jsonb
    ),
    'Should return published non-test future events'
);

-- Should return empty array for non-existing alliance
select is(
    get_alliance_upcoming_events(:'unknownAllianceID'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    '[]'::jsonb,
    'Should return empty array for non-existing alliance'
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
    :'eventCategoryID',
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
        from jsonb_array_elements(
            get_alliance_upcoming_events(:'allianceID'::uuid, array['virtual'])::jsonb
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
            get_alliance_upcoming_events(:'allianceID'::uuid, array['virtual'])::jsonb
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
