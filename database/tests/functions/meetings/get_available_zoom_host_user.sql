-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventHost1OverlapID '00000000-0000-0000-0000-000000000101'
\set eventHost2NonOverlapID '00000000-0000-0000-0000-000000000102'
\set eventHost2OverlapID '00000000-0000-0000-0000-000000000103'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000002'
\set meetingHost1OverlapID '00000000-0000-0000-0000-000000000301'
\set meetingHost2NonOverlapID '00000000-0000-0000-0000-000000000302'
\set meetingHost2OverlapID '00000000-0000-0000-0000-000000000303'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'categoryID', 'Conference', :'communityID');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Group
insert into "group" (group_id, community_id, name, slug, description, group_category_id)
values (:'groupID', :'communityID', 'Test Group', 'test-group', 'A test group', :'groupCategoryID');

-- Event linked to host1 overlap meeting
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
    ends_at
) values (
    :'eventHost1OverlapID',
    :'groupID',
    'Event Host1 Overlap',
    'event-host1-overlap',
    'Event used for host1 overlap load',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2099-06-01 10:00:00-04',
    '2099-06-01 11:00:00-04'
);
insert into meeting (
    meeting_id,
    event_id,
    join_url,
    meeting_provider_id,
    password,
    provider_meeting_id,
    provider_host_user_id
) values (
    :'meetingHost1OverlapID',
    :'eventHost1OverlapID',
    'https://zoom.us/j/host1-overlap',
    'zoom',
    'pass-1',
    'host1-overlap',
    'host1@example.com'
);

-- Event linked to host2 non-overlap meeting
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
    ends_at
) values (
    :'eventHost2NonOverlapID',
    :'groupID',
    'Event Host2 Non Overlap',
    'event-host2-non-overlap',
    'Event used for host2 non-overlap load',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2099-06-01 12:00:00-04',
    '2099-06-01 13:00:00-04'
);
insert into meeting (
    meeting_id,
    event_id,
    join_url,
    meeting_provider_id,
    password,
    provider_meeting_id,
    provider_host_user_id
) values (
    :'meetingHost2NonOverlapID',
    :'eventHost2NonOverlapID',
    'https://zoom.us/j/host2-non-overlap',
    'zoom',
    'pass-2',
    'host2@example.com',
    'host2@example.com'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Returns alphabetical host when no one has overlapping load
select is(
    get_available_zoom_host_user(
        array['host2@example.com', 'host1@example.com'],
        2,
        '2099-06-01 09:00:00-04'::timestamptz,
        '2099-06-01 09:30:00-04'::timestamptz
    ),
    'host1@example.com',
    'Returns alphabetical host when overlap and upcoming counts are tied'
);

-- Excludes host1 when overlap limit is reached
select is(
    get_available_zoom_host_user(
        array['host1@example.com', 'host2@example.com'],
        1,
        '2099-06-01 10:15:00-04'::timestamptz,
        '2099-06-01 10:45:00-04'::timestamptz
    ),
    'host2@example.com',
    'Returns host2 when host1 overlap reaches max slots'
);

-- Keeps host2 eligible when its existing meeting does not overlap
select is(
    get_available_zoom_host_user(
        array['host2@example.com'],
        1,
        '2099-06-01 10:15:00-04'::timestamptz,
        '2099-06-01 10:45:00-04'::timestamptz
    ),
    'host2@example.com',
    'Non-overlapping meetings do not consume simultaneous slots for the same host'
);

-- Enforces 15-minute buffer after existing meeting end for the same host
select is(
    get_available_zoom_host_user(
        array['host1@example.com'],
        1,
        '2099-06-01 11:05:00-04'::timestamptz,
        '2099-06-01 11:20:00-04'::timestamptz
    ),
    null,
    'Returns null when the requested slot falls within the 15-minute buffer window'
);

-- Add an overlapping host2 meeting to exhaust both host slots
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
    ends_at
) values (
    :'eventHost2OverlapID',
    :'groupID',
    'Event Host2 Overlap',
    'event-host2-overlap',
    'Event used for host2 overlap load',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2099-06-01 10:00:00-04',
    '2099-06-01 11:00:00-04'
);
insert into meeting (
    meeting_id,
    event_id,
    join_url,
    meeting_provider_id,
    password,
    provider_meeting_id,
    provider_host_user_id
) values (
    :'meetingHost2OverlapID',
    :'eventHost2OverlapID',
    'https://zoom.us/j/host2-overlap',
    'zoom',
    'pass-3',
    'host2-overlap',
    'host2@example.com'
);

-- Returns null when all hosts are at overlapping limit
select is(
    get_available_zoom_host_user(
        array['host1@example.com', 'host2@example.com'],
        1,
        '2099-06-01 10:15:00-04'::timestamptz,
        '2099-06-01 10:45:00-04'::timestamptz
    ),
    null,
    'Returns null when no host has available overlapping slots'
);

-- Prefers lower upcoming load when overlap counts are tied
select is(
    get_available_zoom_host_user(
        array['host1@example.com', 'host2@example.com'],
        2,
        '2099-06-01 10:15:00-04'::timestamptz,
        '2099-06-01 10:45:00-04'::timestamptz
    ),
    'host1@example.com',
    'Tie-breaks by upcoming load before alphabetical order'
);

-- Returns null for invalid time windows
select is(
    get_available_zoom_host_user(
        array['host1@example.com', 'host2@example.com'],
        2,
        '2099-06-01 10:45:00-04'::timestamptz,
        '2099-06-01 10:15:00-04'::timestamptz
    ),
    null,
    'Returns null when end time is not after start time'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
