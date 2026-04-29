-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000001211'
\set communityID '00000000-0000-0000-0000-000000001201'
\set eventID '00000000-0000-0000-0000-000000001212'
\set groupCategoryID '00000000-0000-0000-0000-000000001210'
\set groupID '00000000-0000-0000-0000-000000001202'
\set meetingID '00000000-0000-0000-0000-000000001214'
\set sessionID '00000000-0000-0000-0000-000000001213'

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

-- Claimed event meeting
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
    current_timestamp,
    'Test Event',
    true,
    'test-event',
    '2026-06-01 10:00:00+00',
    'UTC'
);

-- Claimed session meeting
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
    current_timestamp,
    'Test Session',
    :'sessionID',
    'virtual',
    '2026-06-01 10:00:00+00'
);

-- Claimed orphan meeting
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
    current_timestamp
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release a meeting sync claim
select release_meeting_sync_claim(
    :'eventID',
    null,
    null,
    current_timestamp - interval '1 hour'
);
select isnt(
    (select meeting_sync_claimed_at from event where event_id = :'eventID'),
    null,
    'Should not clear event sync claim for stale claim timestamp'
);
select lives_ok(
    format(
        $$select release_meeting_sync_claim(%L::uuid, null, null, (select meeting_sync_claimed_at from event where event_id = %L::uuid))$$,
        :'eventID',
        :'eventID'
    ),
    'Should release event meeting sync claim'
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

-- Should release a session meeting sync claim
select release_meeting_sync_claim(
    null,
    null,
    :'sessionID',
    current_timestamp - interval '1 hour'
);
select isnt(
    (select meeting_sync_claimed_at from session where session_id = :'sessionID'),
    null,
    'Should not clear session sync claim for stale claim timestamp'
);
select lives_ok(
    format(
        $$select release_meeting_sync_claim(null, null, %L::uuid, (select meeting_sync_claimed_at from session where session_id = %L::uuid))$$,
        :'sessionID',
        :'sessionID'
    ),
    'Should release session meeting sync claim'
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

-- Should release an orphan meeting sync claim
select release_meeting_sync_claim(
    null,
    :'meetingID',
    null,
    current_timestamp - interval '1 hour'
);
select isnt(
    (select sync_claimed_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should not clear orphan meeting sync claim for stale claim timestamp'
);
select lives_ok(
    format(
        $$select release_meeting_sync_claim(null, %L::uuid, null, (select sync_claimed_at from meeting where meeting_id = %L::uuid))$$,
        :'meetingID',
        :'meetingID'
    ),
    'Should release orphan meeting sync claim'
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
