-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000011'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set eventCategoryID '00000000-0000-0000-0000-000000000031'
\set futureEventID '00000000-0000-0000-0000-000000000041'
\set checkInWindowEventID '00000000-0000-0000-0000-000000000042'
\set pastEventID '00000000-0000-0000-0000-000000000043'
\set multiDayEventID '00000000-0000-0000-0000-000000000044'
\set sameDayWithEndsAtEventID '00000000-0000-0000-0000-000000000045'
\set noStartTimeEventID '00000000-0000-0000-0000-000000000046'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
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
    :'communityID',
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'General', 'general', :'communityID');

-- Group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'communityID',
    'Test Group',
    'test-group',
    'A test group',
    :'groupCategoryID'
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

-- Test: is_event_check_in_window_open should return false for future event
select ok(
    not is_event_check_in_window_open(:'communityID'::uuid, :'futureEventID'::uuid),
    'is_event_check_in_window_open returns false for future event'
);

-- Test: is_event_check_in_window_open should return true for event within check-in window
select ok(
    is_event_check_in_window_open(:'communityID'::uuid, :'checkInWindowEventID'::uuid),
    'is_event_check_in_window_open returns true for event within check-in window'
);

-- Test: is_event_check_in_window_open should return false for past event
select ok(
    not is_event_check_in_window_open(:'communityID'::uuid, :'pastEventID'::uuid),
    'is_event_check_in_window_open returns false for past event'
);

-- Test: is_event_check_in_window_open should return true for ongoing multi-day event
select ok(
    is_event_check_in_window_open(:'communityID'::uuid, :'multiDayEventID'::uuid),
    'is_event_check_in_window_open returns true for ongoing multi-day event'
);

-- Test: is_event_check_in_window_open should return true for same-day event with ends_at
select ok(
    is_event_check_in_window_open(:'communityID'::uuid, :'sameDayWithEndsAtEventID'::uuid),
    'is_event_check_in_window_open returns true for same-day event with ends_at'
);

-- Test: is_event_check_in_window_open should return false for event without start time
select ok(
    not is_event_check_in_window_open(:'communityID'::uuid, :'noStartTimeEventID'::uuid),
    'is_event_check_in_window_open returns false for event without start time'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;