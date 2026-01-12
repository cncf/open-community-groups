-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventID '00000000-0000-0000-0000-000000000101'
\set eventWithErrorID '00000000-0000-0000-0000-000000000102'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000002'
\set sessionID '00000000-0000-0000-0000-000000000201'
\set sessionWithErrorID '00000000-0000-0000-0000-000000000202'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner.png');

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

-- Event: needs meeting
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
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'eventID',
    :'groupID',
    'Event Test',
    'event-test',
    'Test event for meeting',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-01 10:00:00-04',
    '2025-06-01 11:00:00-04',

    100,
    false,
    'zoom',
    true
);

-- Session: needs meeting
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
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
    false,
    'zoom',
    true
);

-- Event with previous error: needs meeting
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
    :'eventWithErrorID',
    :'groupID',
    'Event With Error',
    'event-with-error',
    'Test event with previous error',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-02 10:00:00-04',
    '2025-06-02 11:00:00-04',

    100,
    'Previous sync error',
    false,
    'zoom',
    true
);

-- Session with previous error: needs meeting
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
    :'sessionWithErrorID',
    :'eventWithErrorID',
    'Session With Error',
    '2025-06-02 10:00:00-04',
    '2025-06-02 10:30:00-04',
    'virtual',

    'Previous sync error',
    false,
    'zoom',
    true
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create meeting record when linked to event
select add_meeting('zoom', '123456789', 'https://zoom.us/j/123456789', 'pass123', :'eventID', null);
select is(
    (select count(*) from meeting where event_id = :'eventID'),
    1::bigint,
    'Meeting record created for event'
);

-- Should mark event as synced after adding meeting
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    true,
    'Event marked as synced after adding meeting'
);

-- Should create meeting record when linked to session
select add_meeting('zoom', '987654321', 'https://zoom.us/j/987654321', 'sesspass', null, :'sessionID');
select is(
    (select count(*) from meeting where session_id = :'sessionID'),
    1::bigint,
    'Meeting record created for session'
);

-- Should mark session as synced after adding meeting
select is(
    (select meeting_in_sync from session where session_id = :'sessionID'),
    true,
    'Session marked as synced after adding meeting'
);

-- Should fail with unique violation when adding duplicate meeting for same event
select throws_ok(
    format('select add_meeting(''zoom'', ''duplicate123'', ''https://zoom.us/j/duplicate123'', ''pass'', %L, null)', :'eventID'),
    '23505',
    null,
    'Should fail with unique constraint violation'
);

-- Should fail with unique violation when adding duplicate meeting for same session
select throws_ok(
    format('select add_meeting(''zoom'', ''duplicate456'', ''https://zoom.us/j/duplicate456'', ''pass'', null, %L)', :'sessionID'),
    '23505',
    null,
    'Should fail with unique constraint violation'
);

-- Should clear error when adding meeting to event with previous error
select add_meeting('zoom', '111111111', 'https://zoom.us/j/111111111', 'pass111', :'eventWithErrorID', null);
select is(
    (select meeting_error from event where event_id = :'eventWithErrorID'),
    null,
    'Event meeting_error cleared after successful add_meeting'
);

-- Should clear error when adding meeting to session with previous error
select add_meeting('zoom', '222222222', 'https://zoom.us/j/222222222', 'pass222', null, :'sessionWithErrorID');
select is(
    (select meeting_error from session where session_id = :'sessionWithErrorID'),
    null,
    'Session meeting_error cleared after successful add_meeting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
