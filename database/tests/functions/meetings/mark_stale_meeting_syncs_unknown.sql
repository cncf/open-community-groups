-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a0a0000-0000-0000-0000-000000000001'
\set eventCategoryID '7a0a0000-0000-0000-0000-000000000002'
\set eventID '7a0a0000-0000-0000-0000-000000000003'
\set groupCategoryID '7a0a0000-0000-0000-0000-000000000004'
\set groupID '7a0a0000-0000-0000-0000-000000000005'
\set meetingID '7a0a0000-0000-0000-0000-000000000006'
\set sessionID '7a0a0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Stale claimed event meeting
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-01 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'meeting_sync_claimed_at', current_timestamp - interval '30 minutes',
    'published', true,
    'starts_at', '2026-06-01 10:00:00+00'
));

-- Stale claimed session meeting
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
    current_timestamp - interval '30 minutes',
    '2026-06-01 10:00:00+00'
);

-- Stale claimed orphan meeting
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,
    sync_claimed_at
) values (
    :'meetingID',
    'https://zoom.us/j/orphan-stale-syncs',
    'zoom',
    'orphan-stale-syncs',
    current_timestamp - interval '30 minutes'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject non-positive processing timeouts
select throws_ok(
    $$select mark_stale_meeting_syncs_unknown(0)$$,
    'processing timeout must be positive',
    'Should reject non-positive processing timeouts'
);

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
