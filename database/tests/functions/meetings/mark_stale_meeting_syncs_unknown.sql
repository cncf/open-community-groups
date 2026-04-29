-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000001311'
\set communityID '00000000-0000-0000-0000-000000001301'
\set eventID '00000000-0000-0000-0000-000000001312'
\set groupCategoryID '00000000-0000-0000-0000-000000001310'
\set groupID '00000000-0000-0000-0000-000000001302'
\set meetingID '00000000-0000-0000-0000-000000001314'
\set sessionID '00000000-0000-0000-0000-000000001313'

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

-- Stale claimed event meeting
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    meeting_provider_host_user,
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
    'A test event',
    '2026-06-01 11:00:00+00',
    :'categoryID',
    :'eventID',
    'virtual',
    :'groupID',
    false,
    'host@example.com',
    'zoom',
    true,
    current_timestamp - interval '30 minutes',
    'Test Event',
    true,
    'test-event',
    '2026-06-01 10:00:00+00',
    'UTC'
);

-- Stale claimed session meeting
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    '2026-06-01 10:30:00+00',
    :'eventID',
    false,
    'session-host@example.com',
    'zoom',
    true,
    current_timestamp - interval '30 minutes',
    'Test Session',
    :'sessionID',
    'virtual',
    '2026-06-01 10:00:00+00'
);

-- Stale claimed orphan meeting
insert into meeting (
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id,
    sync_claimed_at
) values (
    'https://zoom.us/j/orphan',
    :'meetingID',
    'zoom',
    'orphan',
    current_timestamp - interval '30 minutes'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mark stale sync claims unknown
select is(
    mark_stale_meeting_syncs_unknown(900),
    3,
    'Should mark stale event, session, and orphan meeting sync claims'
);
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    true,
    'Should mark meeting as in sync to stop retries'
);
select is(
    (select meeting_provider_host_user from event where event_id = :'eventID'),
    null,
    'Should clear reserved host'
);
select is(
    (select meeting_sync_claimed_at from event where event_id = :'eventID'),
    null,
    'Should clear event sync claim timestamp'
);
select is(
    (select meeting_in_sync from session where session_id = :'sessionID'),
    true,
    'Should mark session meeting as in sync to stop retries'
);
select is(
    (select meeting_provider_host_user from session where session_id = :'sessionID'),
    null,
    'Should clear session reserved host'
);
select is(
    (select meeting_sync_claimed_at from session where session_id = :'sessionID'),
    null,
    'Should clear session sync claim timestamp'
);
select is(
    (select sync_claimed_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should clear orphan meeting sync claim timestamp'
);
select isnt(
    (select updated_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should update orphan meeting timestamp'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
