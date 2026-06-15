-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set checkInWindowEventID '5e080000-0000-0000-0000-000000000001'
\set communityID '5e080000-0000-0000-0000-000000000002'
\set eventCategoryID '5e080000-0000-0000-0000-000000000003'
\set futureEventID '5e080000-0000-0000-0000-000000000004'
\set groupCategoryID '5e080000-0000-0000-0000-000000000005'
\set groupID '5e080000-0000-0000-0000-000000000006'
\set multiDayEventID '5e080000-0000-0000-0000-000000000007'
\set noStartTimeEventID '5e080000-0000-0000-0000-000000000008'
\set pastEventID '5e080000-0000-0000-0000-000000000009'
\set sameDayWithEndsAtEventID '5e080000-0000-0000-0000-00000000000a'

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
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'A test group'
);

-- Event 1: Future event (outside check-in window)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    published,
    published_at
) values (
    :'futureEventID',
    :'groupID',
    'Future Event',
    'future-event',
    'A future event',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now() + interval '3 hours',
    true,
    now()
);

-- Event 2: Event within check-in window
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    published,
    published_at
) values (
    :'checkInWindowEventID',
    :'groupID',
    'Check-In Window Event',
    'check-in-window-event',
    'An event within check-in window',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now() + interval '1 hour',
    true,
    now()
);

-- Event 3: Past event (outside check-in window)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published,
    published_at
) values (
    :'pastEventID',
    :'groupID',
    'Past Event',
    'past-event',
    'A past event',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now() - interval '2 days',
    now() - interval '1 day',
    true,
    now() - interval '3 days'
);

-- Event 4: Multi-day event still ongoing
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published,
    published_at
) values (
    :'multiDayEventID',
    :'groupID',
    'Multi-Day Event',
    'multi-day-event',
    'A multi-day event spanning multiple days',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now() - interval '1 day',
    now() + interval '1 day',
    true,
    now()
);

-- Event 5: Same day event with ends_at
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published,
    published_at
) values (
    :'sameDayWithEndsAtEventID',
    :'groupID',
    'Same Day Event',
    'same-day-event',
    'An event that starts and ends on the same day',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now() - interval '1 hour',
    now() + interval '1 hour',
    true,
    now()
);

-- Event 6: Event without start time
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    published_at
) values (
    :'noStartTimeEventID',
    :'groupID',
    'No Start Time Event',
    'no-start-time-event',
    'An event without start time',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    now()
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return false for future event
select ok(
    not is_event_check_in_window_open(:'communityID'::uuid, :'futureEventID'::uuid),
    'Should return false for future event'
);

-- Should return true for event within check-in window
select ok(
    is_event_check_in_window_open(:'communityID'::uuid, :'checkInWindowEventID'::uuid),
    'Should return true for event within check-in window'
);

-- Should return false for past event
select ok(
    not is_event_check_in_window_open(:'communityID'::uuid, :'pastEventID'::uuid),
    'Should return false for past event'
);

-- Should return true for ongoing multi-day event
select ok(
    is_event_check_in_window_open(:'communityID'::uuid, :'multiDayEventID'::uuid),
    'Should return true for ongoing multi-day event'
);

-- Should return true for same-day event with ends_at
select ok(
    is_event_check_in_window_open(:'communityID'::uuid, :'sameDayWithEndsAtEventID'::uuid),
    'Should return true for same-day event with ends_at'
);

-- Should return false for event without start time
select ok(
    not is_event_check_in_window_open(:'communityID'::uuid, :'noStartTimeEventID'::uuid),
    'Should return false for event without start time'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
