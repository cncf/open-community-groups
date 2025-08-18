-- Start transaction and plan tests
begin;
select plan(3);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000002'
\set group2ID '00000000-0000-0000-0000-000000000003'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set event1ID '00000000-0000-0000-0000-000000000021'
\set event2ID '00000000-0000-0000-0000-000000000022'
\set event3ID '00000000-0000-0000-0000-000000000023'
\set event4ID '00000000-0000-0000-0000-000000000024'

-- Seed community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community1ID',
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community for testing purposes',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Event kinds are already seeded by the schema, so we don't need to insert them

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'category1ID', 'Conference', 'conference', :'community1ID');

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values ('00000000-0000-0000-0000-000000000010', 'Technology', :'community1ID');

-- Seed groups with location data
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id,
    city,
    state,
    country_code,
    country_name
) values 
    (
        :'group1ID',
        :'community1ID',
        'Test Group',
        'test-group',
        'A test group',
        '00000000-0000-0000-0000-000000000010',
        'San Francisco',
        'CA',
        'US',
        'United States'
    ),
    (
        :'group2ID',
        :'community1ID',
        'Another Group',
        'another-group',
        'Another test group',
        '00000000-0000-0000-0000-000000000010',
        'New York',
        'NY',
        'US',
        'United States'
    );

-- Seed events for group1
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    event_category_id,
    event_kind_id,
    timezone,
    starts_at,
    created_at,
    logo_url,
    venue_city
) values 
    (
        :'event1ID',
        :'group1ID',
        'Future Event',
        'future-event',
        'An event in the future',
        :'category1ID',
        'in-person',
        'America/New_York',
        '2025-12-01 10:00:00+00',
        '2024-01-01 00:00:00',
        'https://example.com/future-logo.png',
        'San Francisco'
    ),
    (
        :'event2ID',
        :'group1ID',
        'Past Event',
        'past-event',
        'An event in the past',
        :'category1ID',
        'virtual',
        'America/Los_Angeles',
        '2024-01-15 14:00:00+00',
        '2024-01-02 00:00:00',
        null,
        null
    ),
    (
        :'event3ID',
        :'group1ID',
        'Event Without Date',
        'event-without-date',
        'An event without a start date',
        :'category1ID',
        'hybrid',
        'Europe/London',
        null,
        '2024-01-03 00:00:00',
        'https://example.com/no-date-logo.png',
        'London'
    ),
    (
        :'event4ID',
        :'group2ID',
        'Other Group Event',
        'other-group-event',
        'Event in different group',
        :'category1ID',
        'in-person',
        'America/Chicago',
        '2025-06-01 09:00:00+00',
        '2024-01-04 00:00:00',
        null,
        'Chicago'
    );

-- Test: list_group_events returns empty array for group with no events
select is(
    list_group_events('00000000-0000-0000-0000-000000000099'::uuid)::text,
    '[]',
    'list_group_events should return empty array for group with no events'
);

-- Test: list_group_events returns full JSON structure for group1 events ordered correctly
select is(
    list_group_events(:'group1ID'::uuid)::jsonb,
    '[
        {
            "event_id": "00000000-0000-0000-0000-000000000021",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "kind": "in-person",
            "name": "Future Event",
            "slug": "future-event",
            "timezone": "America/New_York",
            "group_city": "San Francisco",
            "group_country_code": "US",
            "group_country_name": "United States",
            "group_state": "CA",
            "logo_url": "https://example.com/future-logo.png",
            "starts_at": 1764583200,
            "venue_city": "San Francisco"
        },
        {
            "event_id": "00000000-0000-0000-0000-000000000022",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "kind": "virtual",
            "name": "Past Event",
            "slug": "past-event",
            "timezone": "America/Los_Angeles",
            "group_city": "San Francisco",
            "group_country_code": "US",
            "group_country_name": "United States",
            "group_state": "CA",
            "starts_at": 1705327200
        },
        {
            "event_id": "00000000-0000-0000-0000-000000000023",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "kind": "hybrid",
            "name": "Event Without Date",
            "slug": "event-without-date",
            "timezone": "Europe/London",
            "group_city": "San Francisco",
            "group_country_code": "US",
            "group_country_name": "United States",
            "group_state": "CA",
            "logo_url": "https://example.com/no-date-logo.png",
            "venue_city": "London"
        }
    ]'::jsonb,
    'list_group_events should return events with full JSON structure ordered by starts_at desc with nulls last'
);

-- Test: list_group_events returns full JSON structure for group2's single event
select is(
    list_group_events(:'group2ID'::uuid)::jsonb,
    '[
        {
            "event_id": "00000000-0000-0000-0000-000000000024",
            "group_name": "Another Group",
            "group_slug": "another-group",
            "kind": "in-person",
            "name": "Other Group Event",
            "slug": "other-group-event",
            "timezone": "America/Chicago",
            "group_city": "New York",
            "group_country_code": "US",
            "group_country_name": "United States",
            "group_state": "NY",
            "starts_at": 1748768400,
            "venue_city": "Chicago"
        }
    ]'::jsonb,
    'list_group_events should return correct full JSON for specified group'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;