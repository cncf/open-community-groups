-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '6a030000-0000-0000-0000-000000000001'
\set event1ID '6a030000-0000-0000-0000-000000000002'
\set event2ID '6a030000-0000-0000-0000-000000000003'
\set event3ID '6a030000-0000-0000-0000-000000000004'
\set event4ID '6a030000-0000-0000-0000-000000000005'
\set event5ID '6a030000-0000-0000-0000-000000000006'
\set eventCategoryID '6a030000-0000-0000-0000-000000000007'
\set groupCategoryID '6a030000-0000-0000-0000-000000000008'
\set groupID '6a030000-0000-0000-0000-000000000009'

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
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A test community',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

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
    state
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'Los Angeles',
    'US',
    'United States',
    'CA'
);

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Tech Talks');

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    description_short,
    test_event,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at,
    logo_url,
    venue_city
) values
    -- Past event (should not be included)
    (
        :'event1ID',
        'Past Event',
        'past-event',
        'A past event',
        'A past event',
        false,
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        now() - interval '1 year',
        now() - interval '1 year' + interval '2 hours',
        null,
        'San Francisco'
    ),
    -- Future published event (closest)
    (
        :'event2ID',
        'Future Event 1',
        'future-event-1',
        'First future event',
        'First future event',
        false,
        'UTC',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        true,
        now() + interval '1 month',
        now() + interval '1 month' + interval '2 hours',
        'https://example.com/future-event-1.png',
        'Online'
    ),
    -- Future published event (later)
    (
        :'event3ID',
        'Future Event 2',
        'future-event-2',
        'Second future event',
        'Second future event',
        true,
        'UTC',
        :'eventCategoryID',
        'hybrid',
        :'groupID',
        true,
        now() + interval '2 months',
        now() + interval '2 months' + interval '2 hours',
        'https://example.com/future-event-2.png',
        'Los Angeles'
    ),
    -- Future unpublished event (should not be included)
    (
        :'event4ID',
        'Future Event 3',
        'future-event-3',
        'Unpublished future event',
        'Unpublished future event',
        false,
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        now() + interval '3 months',
        now() + interval '3 months' + interval '2 hours',
        null,
        'New York'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return published non-test future events ordered by date ASC as JSON
select is(
    get_group_upcoming_events(:'communityID'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should return published non-test future events ordered by date ASC as JSON'
);

-- Should return empty array with non-existing group slug
select is(
    get_group_upcoming_events(:'communityID'::uuid, 'non-existing-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    '[]'::jsonb,
    'Should return empty array with non-existing group slug'
);

-- Intentional mid-test seed: verifies deterministic ordering for tied future events
insert into event (
    event_id,
    name,
    slug,
    description,
    description_short,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at,
    logo_url,
    venue_city
) values (
    :'event5ID',
    'Future Event 4',
    'future-event-4',
    'A future event with a tied start time',
    'A future event with a tied start time',
    'UTC',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    true,
    now() + interval '1 month',
    now() + interval '1 month' + interval '4 hours',
    'https://example.com/future-event-4.png',
    'Online'
);

-- Should order tied future events by event ID
select is(
    (
        select jsonb_agg(event_item->>'event_id')
        from jsonb_array_elements(
            get_group_upcoming_events(:'communityID'::uuid, 'test-group', array['virtual'], 10)::jsonb
        ) event_item
    ),
    jsonb_build_array(:'event2ID', :'event5ID'),
    'Should order tied future events by event ID'
);

-- Should resolve upcoming events by pretty slug
update "group" set slug_pretty = 'test-group-pretty' where group_id = :'groupID';
select is(
    get_group_upcoming_events(:'communityID'::uuid, 'test-group-pretty', array['virtual'], 10)::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should resolve upcoming events by pretty slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
