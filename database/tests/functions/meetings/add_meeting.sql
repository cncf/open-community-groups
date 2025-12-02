-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000002'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'

\set eventID '00000000-0000-0000-0000-000000000101'
\set eventWithErrorID '00000000-0000-0000-0000-000000000102'
\set sessionID '00000000-0000-0000-0000-000000000201'
\set sessionWithErrorID '00000000-0000-0000-0000-000000000202'

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

-- Test 1: Add meeting linked to event - verify meeting record created
select add_meeting('zoom', '123456789', 'https://zoom.us/j/123456789', 'pass123', :'eventID', null);
select is(
    (select count(*) from meeting where event_id = :'eventID'),
    1::bigint,
    'Meeting record created for event'
);

-- Test 2: Add meeting linked to event - verify event marked as synced
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    true,
    'Event marked as synced after adding meeting'
);

-- Test 3: Add meeting linked to session - verify meeting record created
select add_meeting('zoom', '987654321', 'https://zoom.us/j/987654321', 'sesspass', null, :'sessionID');
select is(
    (select count(*) from meeting where session_id = :'sessionID'),
    1::bigint,
    'Meeting record created for session'
);

-- Test 4: Add meeting linked to session - verify session marked as synced
select is(
    (select meeting_in_sync from session where session_id = :'sessionID'),
    true,
    'Session marked as synced after adding meeting'
);

-- Test 5: Add duplicate meeting for same event - should fail with unique violation
select throws_ok(
    format('select add_meeting(''zoom'', ''duplicate123'', ''https://zoom.us/j/duplicate123'', ''pass'', %L, null)', :'eventID'),
    '23505',
    null,
    'Adding duplicate meeting for same event fails with unique constraint violation'
);

-- Test 6: Add duplicate meeting for same session - should fail with unique violation
select throws_ok(
    format('select add_meeting(''zoom'', ''duplicate456'', ''https://zoom.us/j/duplicate456'', ''pass'', null, %L)', :'sessionID'),
    '23505',
    null,
    'Adding duplicate meeting for same session fails with unique constraint violation'
);

-- Test 7: Add meeting to event with previous error - verify error cleared
select add_meeting('zoom', '111111111', 'https://zoom.us/j/111111111', 'pass111', :'eventWithErrorID', null);
select is(
    (select meeting_error from event where event_id = :'eventWithErrorID'),
    null,
    'Event meeting_error cleared after successful add_meeting'
);

-- Test 8: Add meeting to session with previous error - verify error cleared
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
