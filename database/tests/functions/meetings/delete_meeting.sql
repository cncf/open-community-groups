-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000002'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'

\set eventID '00000000-0000-0000-0000-000000000101'
\set sessionID '00000000-0000-0000-0000-000000000201'

\set meetingEventID '00000000-0000-0000-0000-000000000301'
\set meetingOrphanID '00000000-0000-0000-0000-000000000303'
\set meetingSessionID '00000000-0000-0000-0000-000000000302'

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
    'test.example.org',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'categoryID', 'Conference', 'conference', :'communityID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

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

-- Event: has meeting to delete (with previous error)
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

    canceled,
    meeting_error,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'eventID',
    :'groupID',
    'Event Test',
    'event-test',
    'Test event for meeting delete',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-01 10:00:00-04',
    '2025-06-01 11:00:00-04',

    true,
    'Previous sync error',
    false,
    'zoom',
    true
);

-- Meeting linked to event
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url, password)
values (:'meetingEventID', :'eventID', 'zoom', '123456789', 'https://zoom.us/j/123456789', 'pass123');

-- Session: has meeting to delete (with previous error)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,

    meeting_error,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionID',
    :'eventID',
    'Session Test',
    '2025-06-01 10:00:00-04',
    '2025-06-01 10:30:00-04',
    'virtual',

    'Previous sync error',
    false,
    'zoom',
    true
);

-- Meeting linked to session
insert into meeting (meeting_id, session_id, meeting_provider_id, provider_meeting_id, join_url, password)
values (:'meetingSessionID', :'sessionID', 'zoom', '987654321', 'https://zoom.us/j/987654321', 'sesspass');

-- Orphan meeting (no event_id or session_id)
insert into meeting (meeting_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingOrphanID', 'zoom', '555666777', 'https://zoom.us/j/555666777');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test 1: Delete meeting linked to event - verify meeting record deleted
select delete_meeting(:'meetingEventID', :'eventID', null);
select is(
    (select count(*) from meeting where meeting_id = :'meetingEventID'),
    0::bigint,
    'Meeting record deleted for event'
);

-- Test 2: Delete meeting linked to event - verify event marked as synced
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    true,
    'Event marked as synced after deleting meeting'
);

-- Test 3: Delete meeting linked to session - verify meeting record deleted
select delete_meeting(:'meetingSessionID', null, :'sessionID');
select is(
    (select count(*) from meeting where meeting_id = :'meetingSessionID'),
    0::bigint,
    'Meeting record deleted for session'
);

-- Test 4: Delete meeting linked to session - verify session marked as synced
select is(
    (select meeting_in_sync from session where session_id = :'sessionID'),
    true,
    'Session marked as synced after deleting meeting'
);

-- Test 5: Delete orphan meeting - verify meeting record deleted
select delete_meeting(:'meetingOrphanID', null, null);
select is(
    (select count(*) from meeting where meeting_id = :'meetingOrphanID'),
    0::bigint,
    'Orphan meeting record deleted'
);

-- Test 6: Delete meeting linked to event - verify previous error cleared
select is(
    (select meeting_error from event where event_id = :'eventID'),
    null,
    'Event meeting_error cleared after successful delete_meeting'
);

-- Test 7: Delete meeting linked to session - verify previous error cleared
select is(
    (select meeting_error from session where session_id = :'sessionID'),
    null,
    'Session meeting_error cleared after successful delete_meeting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
