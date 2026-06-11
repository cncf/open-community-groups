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

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Conference');

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
    description
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'A test group'
);

-- Stale claimed event meeting
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    capacity,
    ends_at,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at,
    published,
    starts_at,
    timezone
) values (
    :'eventID',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Test Event',
    'test-event',
    'A test event',
    100,
    '2026-06-01 11:00:00+00',
    false,
    'host@example.com',
    'zoom',
    true,
    current_timestamp - interval '30 minutes',
    true,
    '2026-06-01 10:00:00+00',
    'UTC'
);

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
    'https://zoom.us/j/orphan',
    'zoom',
    'orphan',
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
