-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventID '00000000-0000-0000-0000-000000000101'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000002'
\set meetingEventID '00000000-0000-0000-0000-000000000301'
\set meetingSessionID '00000000-0000-0000-0000-000000000302'
\set sessionID '00000000-0000-0000-0000-000000000201'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

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

-- Event: has meeting to update (with previous error)
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

    capacity,
    meeting_error,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'eventID',
    :'groupID',
    'Event Test',
    'event-test',
    'Test event for meeting update',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-01 10:00:00-04',
    '2025-06-01 11:00:00-04',

    100,
    'Previous sync error',
    false,
    'zoom',
    true
);

-- Meeting linked to event
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url, password)
values (:'meetingEventID', :'eventID', 'zoom', '123456789', 'https://zoom.us/j/123456789', 'pass123');

-- Session: has meeting to update (with previous error)
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

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update meeting record when linked to event
select update_meeting(:'meetingEventID', '111222333', 'https://zoom.us/j/111222333', 'newpass', :'eventID', null);
select is(
    (select provider_meeting_id from meeting where meeting_id = :'meetingEventID'),
    '111222333',
    'Meeting record updated for event'
);

-- Should mark event as synced after updating meeting
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    true,
    'Event marked as synced after updating meeting'
);

-- Mark event as out of sync again for next test
update event set meeting_in_sync = false where event_id = :'eventID';

-- Should update meeting record when linked to session
select update_meeting(:'meetingSessionID', '444555666', 'https://zoom.us/j/444555666', 'newsesspass', null, :'sessionID');
select is(
    (select provider_meeting_id from meeting where meeting_id = :'meetingSessionID'),
    '444555666',
    'Meeting record updated for session'
);

-- Should mark session as synced after updating meeting
select is(
    (select meeting_in_sync from session where session_id = :'sessionID'),
    true,
    'Session marked as synced after updating meeting'
);

-- Should clear previous error when updating meeting linked to event
select is(
    (select meeting_error from event where event_id = :'eventID'),
    null,
    'Event meeting_error cleared after successful update_meeting'
);

-- Should clear previous error when updating meeting linked to session
select is(
    (select meeting_error from session where session_id = :'sessionID'),
    null,
    'Session meeting_error cleared after successful update_meeting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
