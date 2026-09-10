-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(15);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a0c0000-0000-0000-0000-000000000001'
\set eventCategoryID '7a0c0000-0000-0000-0000-000000000002'
\set eventID '7a0c0000-0000-0000-0000-000000000003'
\set groupCategoryID '7a0c0000-0000-0000-0000-000000000004'
\set groupID '7a0c0000-0000-0000-0000-000000000005'
\set meetingID '7a0c0000-0000-0000-0000-000000000006'
\set sessionID '7a0c0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Claimed event meeting
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-01 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'meeting_sync_claimed_at', current_timestamp,
    'published', true,
    'starts_at', '2026-06-01 10:00:00+00'
));

-- Claimed session meeting
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    ends_at,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at,
    starts_at
) values (
    :'sessionID',
    :'eventID',
    'Test Session',
    'virtual',
    '2026-06-01 10:30:00+00',
    false,
    'session-host@example.com',
    'zoom',
    true,
    current_timestamp,
    '2026-06-01 10:00:00+00'
);

-- Claimed orphan meeting
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,
    sync_claimed_at
) values (
    :'meetingID',
    'https://zoom.us/j/orphan-release-meeting-sync-claim',
    'zoom',
    'orphan-release-meeting-sync-claim',
    current_timestamp
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release a meeting sync claim
select lives_ok(
    format(
        $$select release_meeting_sync_claim(%L::uuid, null, null, current_timestamp - interval '1 hour')$$,
        :'eventID'
    ),
    'Should accept a stale event claim timestamp without error'
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
select lives_ok(
    format(
        $$select release_meeting_sync_claim(null, null, %L::uuid, current_timestamp - interval '1 hour')$$,
        :'sessionID'
    ),
    'Should accept a stale session claim timestamp without error'
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
select lives_ok(
    format(
        $$select release_meeting_sync_claim(null, %L::uuid, null, current_timestamp - interval '1 hour')$$,
        :'meetingID'
    ),
    'Should accept a stale orphan meeting claim timestamp without error'
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
