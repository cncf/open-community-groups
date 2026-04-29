-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000001611'
\set communityID '00000000-0000-0000-0000-000000001601'
\set eventClaimedID '00000000-0000-0000-0000-000000001612'
\set eventHost1OverlapID '00000000-0000-0000-0000-000000001614'
\set eventHost2NonOverlapID '00000000-0000-0000-0000-000000001615'
\set eventHost2OverlapID '00000000-0000-0000-0000-000000001616'
\set eventSelectionID '00000000-0000-0000-0000-000000001617'
\set eventSessionParentID '00000000-0000-0000-0000-000000001618'
\set eventStaleClaimID '00000000-0000-0000-0000-000000001619'
\set groupCategoryID '00000000-0000-0000-0000-000000001610'
\set groupID '00000000-0000-0000-0000-000000001602'
\set meetingHost1OverlapID '00000000-0000-0000-0000-000000001631'
\set meetingHost2NonOverlapID '00000000-0000-0000-0000-000000001632'
\set meetingHost2OverlapID '00000000-0000-0000-0000-000000001633'
\set sessionClaimedID '00000000-0000-0000-0000-000000001613'
\set sessionStaleClaimID '00000000-0000-0000-0000-000000001620'

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
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, description)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group', 'A test group');

-- Event used for selection-only calls without persisting a reservation
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    100,
    'Selection owner event',
    '2099-06-01 09:30:00-04',
    :'categoryID',
    :'eventSelectionID',
    'virtual',
    :'groupID',
    false,
    'zoom',
    true,
    'Selection Owner Event',
    true,
    'selection-owner-event',
    '2099-06-01 09:00:00-04',
    'America/New_York'
);

-- Claimed event meeting requiring host assignment
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    100,
    'Claimed event',
    '2026-06-01 11:00:00+00',
    :'categoryID',
    :'eventClaimedID',
    'virtual',
    :'groupID',
    false,
    'zoom',
    true,
    current_timestamp,
    'Claimed Event',
    true,
    'claimed-event',
    '2026-06-01 10:00:00+00',
    'UTC'
);

-- Event with newer claim than the worker attempting host assignment
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    100,
    'Stale claimed event',
    '2026-06-03 11:00:00+00',
    :'categoryID',
    :'eventStaleClaimID',
    'virtual',
    :'groupID',
    false,
    'zoom',
    true,
    current_timestamp,
    'Stale Claimed Event',
    true,
    'stale-claimed-event',
    '2026-06-03 10:00:00+00',
    'UTC'
);

-- Parent event for claimed session assignment
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    100,
    'Parent event for session assignment',
    '2026-06-02 11:00:00+00',
    :'categoryID',
    :'eventSessionParentID',
    'virtual',
    :'groupID',
    true,
    'zoom',
    true,
    'Session Parent Event',
    true,
    'session-parent-event',
    '2026-06-02 10:00:00+00',
    'UTC'
);

-- Session with newer claim than the worker attempting host assignment
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    '2026-06-02 11:00:00+00',
    :'eventSessionParentID',
    false,
    'zoom',
    true,
    current_timestamp,
    'Stale Claimed Session',
    :'sessionStaleClaimID',
    'virtual',
    '2026-06-02 10:30:00+00'
);

-- Claimed session meeting requiring host assignment
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    '2026-06-02 10:30:00+00',
    :'eventSessionParentID',
    false,
    'zoom',
    true,
    current_timestamp,
    'Claimed Session',
    :'sessionClaimedID',
    'virtual',
    '2026-06-02 10:00:00+00'
);

-- Event linked to host1 overlap meeting
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    100,
    'Event used for host1 overlap load',
    '2099-06-01 11:00:00-04',
    :'categoryID',
    :'eventHost1OverlapID',
    'virtual',
    :'groupID',
    'Event Host1 Overlap',
    true,
    'event-host1-overlap',
    '2099-06-01 10:00:00-04',
    'America/New_York'
);

-- Event linked to host2 non-overlap meeting
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    100,
    'Event used for host2 non-overlap load',
    '2099-06-01 13:00:00-04',
    :'categoryID',
    :'eventHost2NonOverlapID',
    'virtual',
    :'groupID',
    'Event Host2 Non Overlap',
    true,
    'event-host2-non-overlap',
    '2099-06-01 12:00:00-04',
    'America/New_York'
);

-- Event linked to initially unassigned host2 overlap meeting
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    100,
    'Event used for host2 overlap load',
    '2099-06-01 11:00:00-04',
    :'categoryID',
    :'eventHost2OverlapID',
    'virtual',
    :'groupID',
    'Event Host2 Overlap',
    true,
    'event-host2-overlap',
    '2099-06-01 10:00:00-04',
    'America/New_York'
);

-- Existing Zoom meetings used for host load calculations
insert into meeting (
    event_id,
    join_url,
    meeting_id,
    meeting_provider_id,
    password,
    provider_host_user_id,
    provider_meeting_id
) values
(
    :'eventHost1OverlapID',
    'https://zoom.us/j/host1-overlap',
    :'meetingHost1OverlapID',
    'zoom',
    'pass-1',
    'host1@example.com',
    'host1-overlap'
),
(
    :'eventHost2NonOverlapID',
    'https://zoom.us/j/host2-non-overlap',
    :'meetingHost2NonOverlapID',
    'zoom',
    'pass-2',
    'host2@example.com',
    'host2@example.com'
),
(
    :'eventHost2OverlapID',
    'https://zoom.us/j/host2-overlap',
    :'meetingHost2OverlapID',
    'zoom',
    'pass-3',
    null,
    'host2-overlap'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Returns alphabetical host when no one has overlapping load
select is(
    assign_zoom_host_user(
        :'eventSelectionID',
        null,
        null,
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
    assign_zoom_host_user(
        :'eventSelectionID',
        null,
        null,
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
    assign_zoom_host_user(
        :'eventSelectionID',
        null,
        null,
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
    assign_zoom_host_user(
        :'eventSelectionID',
        null,
        null,
        array['host1@example.com'],
        1,
        '2099-06-01 11:05:00-04'::timestamptz,
        '2099-06-01 11:20:00-04'::timestamptz
    ),
    null,
    'Returns null when the requested slot falls within the 15-minute buffer window'
);

-- Assign the overlapping host2 meeting to exhaust both host slots
update meeting
set provider_host_user_id = 'host2@example.com'
where meeting_id = :'meetingHost2OverlapID';

-- Returns null when all hosts are at overlapping limit
select is(
    assign_zoom_host_user(
        :'eventSelectionID',
        null,
        null,
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
    assign_zoom_host_user(
        :'eventSelectionID',
        null,
        null,
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
    assign_zoom_host_user(
        :'eventSelectionID',
        null,
        null,
        array['host1@example.com', 'host2@example.com'],
        2,
        '2099-06-01 10:45:00-04'::timestamptz,
        '2099-06-01 10:15:00-04'::timestamptz
    ),
    null,
    'Returns null when end time is not after start time'
);

-- Should reserve a Zoom host on the claimed event
select is(
    assign_zoom_host_user(
        :'eventClaimedID',
        null,
        (select meeting_sync_claimed_at from event where event_id = :'eventClaimedID'),
        array['host@example.com'],
        1,
        '2026-06-01 10:00:00+00',
        '2026-06-01 11:00:00+00'
    ),
    'host@example.com',
    'Should return available host for claimed event'
);
select is(
    (select meeting_provider_host_user from event where event_id = :'eventClaimedID'),
    'host@example.com',
    'Should store event host reservation'
);
select is(
    assign_zoom_host_user(
        :'eventStaleClaimID',
        null,
        current_timestamp - interval '1 hour',
        array['stale-host@example.com'],
        1,
        '2026-06-03 10:00:00+00',
        '2026-06-03 11:00:00+00'
    ),
    null,
    'Should return null when event claim timestamp does not match'
);
select is(
    (select meeting_provider_host_user from event where event_id = :'eventStaleClaimID'),
    null,
    'Should not store event host reservation for stale claim'
);
select is(
    assign_zoom_host_user(
        :'eventClaimedID',
        null,
        (select meeting_sync_claimed_at from event where event_id = :'eventClaimedID'),
        array['host@example.com'],
        1,
        '2026-06-01 10:00:00+00',
        '2026-06-01 11:00:00+00'
    ),
    null,
    'Should count event host reservations when checking capacity'
);

-- Should reserve a Zoom host on the claimed session
select is(
    assign_zoom_host_user(
        null,
        :'sessionClaimedID',
        (select meeting_sync_claimed_at from session where session_id = :'sessionClaimedID'),
        array['session-host@example.com'],
        1,
        '2026-06-02 10:00:00+00',
        '2026-06-02 10:30:00+00'
    ),
    'session-host@example.com',
    'Should return available host for claimed session'
);
select is(
    (select meeting_provider_host_user from session where session_id = :'sessionClaimedID'),
    'session-host@example.com',
    'Should store session host reservation'
);
select is(
    assign_zoom_host_user(
        null,
        :'sessionStaleClaimID',
        current_timestamp - interval '1 hour',
        array['stale-session-host@example.com'],
        1,
        '2026-06-02 10:30:00+00',
        '2026-06-02 11:00:00+00'
    ),
    null,
    'Should return null when session claim timestamp does not match'
);
select is(
    (select meeting_provider_host_user from session where session_id = :'sessionStaleClaimID'),
    null,
    'Should not store session host reservation for stale claim'
);
select is(
    assign_zoom_host_user(
        :'eventSelectionID',
        null,
        null,
        array['session-host@example.com'],
        1,
        '2026-06-02 10:00:00+00',
        '2026-06-02 10:30:00+00'
    ),
    null,
    'Should count session host reservations when checking capacity'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
