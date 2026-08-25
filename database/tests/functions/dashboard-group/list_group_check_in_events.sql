-- Tests listing current and upcoming events for group check-in scanners.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '3a2c0000-0000-0000-0000-000000000009'
\set communityID '3a2c0000-0000-0000-0000-000000000001'
\set currentEventID '3a2c0000-0000-0000-0000-000000000002'
\set endedEventID '3a2c0000-0000-0000-0000-000000000008'
\set eventCategoryID '3a2c0000-0000-0000-0000-000000000003'
\set futureEventID '3a2c0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a2c0000-0000-0000-0000-000000000005'
\set groupID '3a2c0000-0000-0000-0000-000000000006'
\set pastEventID '3a2c0000-0000-0000-0000-000000000007'
\set unpublishedEventID '3a2c0000-0000-0000-0000-000000000010'
\set unscheduledEventID '3a2c0000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the listed events
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'A test community',
    'Test Community',
    'https://example.com/logo.png',
    'test-community'
);

-- Group category used by the scanner group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category used by scanner events
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Group owning the scanner events
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Current, future, explicitly ended, and expired events used by visibility scenarios
insert into event (
    event_id,
    description,
    ends_at,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    published_at,
    slug,
    starts_at,
    timezone
) values
    (
        :'currentEventID',
        'A current event',
        current_timestamp + interval '1 hour',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Current Event',
        true,
        current_timestamp - interval '2 hours',
        'current-event',
        current_timestamp - interval '1 hour',
        'UTC'
    ),
    (
        :'endedEventID',
        'An event that ended earlier on its local day',
        date_trunc('day', current_timestamp at time zone 'UTC') at time zone 'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Ended Event',
        true,
        current_timestamp - interval '1 day',
        'ended-event',
        (
            date_trunc('day', current_timestamp at time zone 'UTC') - interval '1 hour'
        ) at time zone 'UTC',
        'UTC'
    ),
    (
        :'futureEventID',
        'A future event',
        null,
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Future Event',
        true,
        current_timestamp,
        'future-event',
        current_timestamp + interval '1 day',
        'UTC'
    ),
    (
        :'pastEventID',
        'A past event',
        current_timestamp - interval '2 days',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Past Event',
        true,
        current_timestamp - interval '4 days',
        'past-event',
        current_timestamp - interval '3 days',
        'UTC'
    );

-- Canceled, unpublished, and unscheduled events excluded from the scanner
insert into event (
    event_id,
    canceled,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    published_at,
    slug,
    starts_at,
    timezone
) values
    (
        :'canceledEventID',
        true,
        'A canceled event',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Canceled Event',
        true,
        current_timestamp,
        'canceled-event',
        current_timestamp + interval '2 days',
        'UTC'
    ),
    (
        :'unpublishedEventID',
        false,
        'An unpublished event',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Unpublished Event',
        false,
        null,
        'unpublished-event',
        current_timestamp + interval '2 days',
        'UTC'
    ),
    (
        :'unscheduledEventID',
        false,
        'An unscheduled event',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Unscheduled Event',
        true,
        current_timestamp,
        'unscheduled-event',
        null,
        'UTC'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list in-progress events before upcoming events
select results_eq(
    format(
        $$
            select value->>'event_id'
            from json_array_elements(list_group_check_in_events(%L::uuid)) value
        $$,
        :'groupID'
    ),
    format(
        $$ values (%L::text), (%L::text) $$,
        :'currentEventID',
        :'futureEventID'
    ),
    'Should list in-progress events before upcoming events'
);

-- Should return only narrow scanner fields
select ok(
    not list_group_check_in_events(:'groupID'::uuid)::text like '%check_in_code%',
    'Should return only narrow scanner fields'
);

-- Should return the exact scanner card contract
select results_eq(
    format(
        $$
            select key
            from json_each((list_group_check_in_events(%L::uuid)->0))
            order by key
        $$,
        :'groupID'
    ),
    $$
        values
            ('event_id'),
            ('in_progress'),
            ('kind'),
            ('location'),
            ('logo_url'),
            ('name'),
            ('starts_at'),
            ('timezone')
    $$,
    'Should return the exact scanner card contract'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
