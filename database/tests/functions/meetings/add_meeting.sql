-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

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
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'categoryID', 'Conference', :'communityID');

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
select lives_ok(
    format(
        'select add_meeting(''zoom'', ''123456789'', ''host-event@example.com'', ''https://zoom.us/j/123456789'', ''pass123'', %L, null)',
        :'eventID'
    ),
    'Should create meeting record when linked to event'
);
select results_eq(
    format(
        $query$
        select
            event_id,
            join_url,
            meeting_provider_id,
            provider_host_user_id,
            provider_meeting_id,

            password,
            recording_url,
            session_id,
            updated_at,

            created_at is not null as has_created_at,
            meeting_id is not null as has_meeting_id
        from meeting
        where event_id = %L::uuid
        $query$,
        :'eventID'
    ),
    format(
        $expected$
        values (
            %L::uuid,
            'https://zoom.us/j/123456789',
            'zoom',
            'host-event@example.com',
            '123456789',

            'pass123',
            null,
            null::uuid,
            null::timestamptz,

            true,
            true
        )
        $expected$,
        :'eventID'
    ),
    'Meeting record created for event with expected fields'
);

-- Should mark event as synced after adding meeting
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    true,
    'Event marked as synced after adding meeting'
);

-- Should create meeting record when linked to session
select lives_ok(
    format(
        'select add_meeting(''zoom'', ''987654321'', ''host-session@example.com'', ''https://zoom.us/j/987654321'', ''sesspass'', null, %L)',
        :'sessionID'
    ),
    'Should create meeting record when linked to session'
);
select results_eq(
    format(
        $query$
        select
            join_url,
            meeting_provider_id,
            provider_host_user_id,
            provider_meeting_id,
            session_id,

            event_id,
            password,
            recording_url,
            updated_at,

            created_at is not null as has_created_at,
            meeting_id is not null as has_meeting_id
        from meeting
        where session_id = %L::uuid
        $query$,
        :'sessionID'
    ),
    format(
        $expected$
        values (
            'https://zoom.us/j/987654321',
            'zoom',
            'host-session@example.com',
            '987654321',
            %L::uuid,

            null::uuid,
            'sesspass',
            null,
            null::timestamptz,

            true,
            true
        )
        $expected$,
        :'sessionID'
    ),
    'Meeting record created for session with expected fields'
);

-- Should mark session as synced after adding meeting
select is(
    (select meeting_in_sync from session where session_id = :'sessionID'),
    true,
    'Session marked as synced after adding meeting'
);

-- Should fail with unique violation when adding duplicate meeting for same event
select throws_ok(
    format(
        'select add_meeting(''zoom'', ''duplicate123'', ''host-event@example.com'', ''https://zoom.us/j/duplicate123'', ''pass'', %L, null)',
        :'eventID'
    ),
    '23505',
    null,
    'Should fail with unique constraint violation for duplicate event meeting'
);

-- Should fail with unique violation when adding duplicate meeting for same session
select throws_ok(
    format(
        'select add_meeting(''zoom'', ''duplicate456'', ''host-session@example.com'', ''https://zoom.us/j/duplicate456'', ''pass'', null, %L)',
        :'sessionID'
    ),
    '23505',
    null,
    'Should fail with unique constraint violation for duplicate session meeting'
);

-- Should clear error when adding meeting to event with previous error
select lives_ok(
    format(
        'select add_meeting(''zoom'', ''111111111'', ''host-error-event@example.com'', ''https://zoom.us/j/111111111'', ''pass111'', %L, null)',
        :'eventWithErrorID'
    ),
    'Should clear error when adding meeting to event with previous error'
);
select is(
    (select meeting_error from event where event_id = :'eventWithErrorID'),
    null,
    'Event meeting_error cleared after successful add_meeting'
);

-- Should clear error when adding meeting to session with previous error
select lives_ok(
    format(
        'select add_meeting(''zoom'', ''222222222'', ''host-error-session@example.com'', ''https://zoom.us/j/222222222'', ''pass222'', null, %L)',
        :'sessionWithErrorID'
    ),
    'Should clear error when adding meeting to session with previous error'
);
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
