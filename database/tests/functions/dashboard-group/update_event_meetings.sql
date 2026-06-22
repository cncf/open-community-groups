-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(26);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set category1ID '3a3b0000-0000-0000-0000-000000000001'
\set alliance1ID '3a3b0000-0000-0000-0000-000000000002'
\set event5ID '3a3b0000-0000-0000-0000-000000000003'
\set event6ID '3a3b0000-0000-0000-0000-000000000004'
\set event7ID '3a3b0000-0000-0000-0000-000000000005'
\set event25ID '3a3b0000-0000-0000-0000-000000000006'
\set event26ID '3a3b0000-0000-0000-0000-000000000007'
\set group1ID '3a3b0000-0000-0000-0000-000000000008'
\set meeting1ID '3a3b0000-0000-0000-0000-000000000009'
\set meeting2ID '3a3b0000-0000-0000-0000-000000000010'
\set meeting3ID '3a3b0000-0000-0000-0000-000000000011'
\set meeting4ID '3a3b0000-0000-0000-0000-000000000012'
\set meeting5ID '3a3b0000-0000-0000-0000-000000000013'
\set session1ID '3a3b0000-0000-0000-0000-000000000014'
\set session2ID '3a3b0000-0000-0000-0000-000000000015'
\set session4ID '3a3b0000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'alliance1ID',
    'test-alliance',
    'Test Alliance',
    'A test alliance for testing purposes',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event Category
insert into event_category (event_category_id, name, alliance_id)
values (:'category1ID', 'Conference', :'alliance1ID');

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values ('3a3b0000-0000-0000-0000-000000000017', 'Technology', :'alliance1ID');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'group1ID',
    :'alliance1ID',
    'Test Group',
    'abc1234',
    'A test group',
    '3a3b0000-0000-0000-0000-000000000017'
);

-- Event with meeting_in_sync=false for testing preservation
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    meeting_provider_id,
    meeting_requested,
    meeting_in_sync,
    published,
    starts_at,
    ends_at
) values (
    :'event5ID',
    :'group1ID',
    'Event With Pending Sync',
    'ghi9abc',
    'This event has a pending meeting sync',
    'America/New_York',
    :'category1ID',
    'virtual',
    100,
    'zoom',
    true,
    false,
    true,
    '2030-03-01 10:00:00-05',
    '2030-03-01 12:00:00-05'
);

-- Event meeting for meeting_in_sync=false preservation
insert into meeting (
    event_id,
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id,
    recording_urls
) values (
    :'event5ID',
    'https://zoom.us/j/event-pending-sync',
    :'meeting2ID',
    'zoom',
    'event-pending-sync',
    array['https://zoom.example/event-pending-recording']::text[]
);

-- Started event with synced automatic meeting
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    published,
    starts_at,
    ends_at
) values (
    :'event25ID',
    :'group1ID',
    'Started Synced Event',
    'started-synced-event',
    'This event started with a synced automatic meeting',
    'UTC',
    :'category1ID',
    'virtual',
    100,
    true,
    'zoom',
    true,
    true,
    '2020-02-01 10:00:00+00',
    '2020-02-01 12:00:00+00'
);

-- Started event meeting for archived sync checks
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (
    :'event25ID',
    'https://zoom.us/j/started-event',
    :'meeting4ID',
    'zoom',
    'started-event'
);

-- Event with session having meeting_in_sync=false
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
    ends_at
) values (
    :'event6ID',
    :'group1ID',
    'Event With Session Pending Sync',
    'jkl2def',
    'This event has a session with pending meeting sync',
    'America/New_York',
    :'category1ID',
    'virtual',
    '2030-04-01 09:00:00-04',
    '2030-04-01 17:00:00-04'
);

-- Session with pending meeting sync for preservation checks
insert into session (
    session_id,
    event_id,
    name,
    description,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested,
    meeting_in_sync
) values (
    :'session1ID',
    :'event6ID',
    'Session With Pending Sync',
    'Session description',
    '2030-04-01 10:00:00-04',
    '2030-04-01 11:00:00-04',
    'virtual',
    'zoom',
    true,
    false
);

-- Session meeting for meeting_in_sync=false preservation
insert into meeting (
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id,
    recording_urls,
    session_id
) values (
    'https://zoom.us/j/session-pending-sync',
    :'meeting3ID',
    'zoom',
    'session-pending-sync',
    array['https://zoom.example/session-pending-recording']::text[],
    :'session1ID'
);

-- Started session with synced automatic meeting
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at,
    ends_at
) values (
    :'event26ID',
    :'group1ID',
    'Started Session Parent Event',
    'started-session-parent-event',
    'This event started with a synced session meeting',
    'UTC',
    :'category1ID',
    'virtual',
    100,
    true,
    '2020-02-02 09:00:00+00',
    '2020-02-02 13:00:00+00'
);

-- Started session row for archived sync checks
insert into session (
    session_id,
    event_id,
    name,
    description,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'session4ID',
    :'event26ID',
    'Started Synced Session',
    'Started synced session description',
    '2020-02-02 10:00:00+00',
    '2020-02-02 11:00:00+00',
    'virtual',
    true,
    'zoom',
    true
);

-- Started session meeting for archived sync checks
insert into meeting (join_url, meeting_id, meeting_provider_id, provider_meeting_id, session_id)
values (
    'https://zoom.us/j/started-session',
    :'meeting5ID',
    'zoom',
    'started-session',
    :'session4ID'
);

-- Event with session that has a meeting (for orphan test)
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
    published
) values (
    :'event7ID',
    :'group1ID',
    'Event For Session Removal Test',
    'mno3ghi',
    'This event has a session with a meeting',
    'America/New_York',
    :'category1ID',
    'virtual',
    '2030-05-01 09:00:00-04',
    '2030-05-01 17:00:00-04',
    true
);

-- Existing session row for removal/orphan checks
insert into session (
    session_id,
    event_id,
    name,
    description,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested,
    meeting_in_sync
) values (
    :'session2ID',
    :'event7ID',
    'Session To Be Removed',
    'Session description',
    '2030-05-01 10:00:00-04',
    '2030-05-01 11:00:00-04',
    'virtual',
    'zoom',
    true,
    true
);

-- Existing session meeting for removal/orphan checks
insert into meeting (join_url, meeting_id, meeting_provider_id, provider_meeting_id, session_id)
values ('https://zoom.us/j/123123123', :'meeting1ID', 'zoom', '123123123', :'session2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should preserve meeting_in_sync=false when updating unrelated fields
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000003'::uuid,
        '{
            "name": "Event With Pending Sync",
            "description": "Updated description - unrelated to meeting",
            "timezone": "America/New_York",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "capacity": 100,
            "meeting_provider_id": "zoom",
            "meeting_requested": true,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T12:00:00"
        }'::jsonb
    )$$,
    'Should execute unrelated update with pending event meeting sync'
);
select is(
    (select meeting_in_sync from event where event_id = :'event5ID'::uuid),
    false,
    'Should keep event meeting_in_sync=false after unrelated update'
);

-- Should keep meeting_in_sync=false when meeting_requested changes to false
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000003'::uuid,
        '{
            "name": "Event With Pending Sync",
            "description": "Updated description",
            "timezone": "America/New_York",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "meeting_requested": false,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T12:00:00"
        }'::jsonb
    )$$,
    'Should execute update when event meeting_requested changes to false'
);
select is(
    (select meeting_in_sync from event where event_id = :'event5ID'::uuid),
    false,
    'Should keep event meeting_in_sync=false when meeting_requested changes to false'
);

-- Should persist event recording override for automatic meetings
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000003'::uuid,
        '{
            "name": "Event With Pending Sync",
            "description": "Updated description with recording override",
            "timezone": "America/New_York",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "capacity": 100,
            "kind_id": "virtual",
            "meeting_provider_id": "zoom",
            "meeting_recording_published": false,
            "meeting_recording_requested": false,
            "meeting_recording_url": "https://youtube.com/watch?v=event-override",
            "meeting_requested": true,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T12:00:00"
        }'::jsonb
    )$$,
    'Should execute update when automatic event meeting recording override is provided'
);
select is(
    (select meeting_recording_url from event where event_id = :'event5ID'::uuid),
    'https://youtube.com/watch?v=event-override',
    'Should persist event recording override for automatic meetings'
);
select is(
    (select meeting_recording_published from event where event_id = :'event5ID'::uuid),
    false,
    'Should persist event recording visibility when unpublished'
);
select is(
    (select meeting_recording_requested from event where event_id = :'event5ID'::uuid),
    false,
    'Should persist event meeting recording preference when disabled'
);

-- Should clear event recording override and fall back to synced meeting recording
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000003'::uuid,
        '{
            "name": "Event With Pending Sync",
            "description": "Updated description with cleared recording override",
            "timezone": "America/New_York",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "capacity": 100,
            "kind_id": "virtual",
            "meeting_provider_id": "zoom",
            "meeting_recording_url": "",
            "meeting_requested": true,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T12:00:00"
        }'::jsonb
    )$$,
    'Should execute update when automatic event meeting recording override is cleared'
);
select is(
    (
        select get_event_full(
            :'alliance1ID'::uuid,
            :'group1ID'::uuid,
            :'event5ID'::uuid
        )::jsonb->>'meeting_recording_public_url'
    ),
    null::text,
    'Should keep synced event meeting recording hidden after clearing unpublished override'
);

-- Should preserve session meeting_in_sync=false when updating unrelated fields
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000004'::uuid,
        '{
            "name": "Event With Session Pending Sync",
            "description": "Updated event description - unrelated to session meeting",
            "timezone": "America/New_York",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "starts_at": "2030-04-01T09:00:00",
            "ends_at": "2030-04-01T17:00:00",
            "sessions": [
                {
                    "session_id": "3a3b0000-0000-0000-0000-000000000014",
                    "name": "Session With Pending Sync",
                    "description": "Updated session description - unrelated to meeting",
                    "starts_at": "2030-04-01T10:00:00",
                    "ends_at": "2030-04-01T11:00:00",
                    "kind": "virtual",
                    "meeting_provider_id": "zoom",
                    "meeting_requested": true
                }
            ]
        }'::jsonb
    )$$,
    'Should execute unrelated update with pending session meeting sync'
);
select is(
    (select meeting_in_sync from session where session_id = :'session1ID'::uuid),
    false,
    'Should keep session meeting_in_sync=false after unrelated update'
);

-- Should keep session meeting_in_sync=false when meeting_requested changes to false
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000004'::uuid,
        '{
            "name": "Event With Session Pending Sync",
            "description": "Updated event description",
            "timezone": "America/New_York",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "starts_at": "2030-04-01T09:00:00",
            "ends_at": "2030-04-01T17:00:00",
            "sessions": [
                {
                    "session_id": "3a3b0000-0000-0000-0000-000000000014",
                    "name": "Session With Pending Sync",
                    "description": "Updated session description",
                    "starts_at": "2030-04-01T10:00:00",
                    "ends_at": "2030-04-01T11:00:00",
                    "kind": "virtual",
                    "meeting_requested": false
                }
            ]
        }'::jsonb
    )$$,
    'Should execute update when session meeting_requested changes to false'
);
select is(
    (select meeting_in_sync from session where session_id = :'session1ID'::uuid),
    false,
    'Should keep session meeting_in_sync=false when meeting_requested changes to false'
);

-- Should persist session recording override for automatic meetings
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000004'::uuid,
        '{
            "name": "Event With Session Pending Sync",
            "description": "Updated event description with session recording override",
            "timezone": "America/New_York",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "starts_at": "2030-04-01T09:00:00",
            "ends_at": "2030-04-01T17:00:00",
            "sessions": [
                {
                    "session_id": "3a3b0000-0000-0000-0000-000000000014",
                    "name": "Session With Pending Sync",
                    "description": "Updated session description with recording override",
                    "starts_at": "2030-04-01T10:00:00",
                    "ends_at": "2030-04-01T11:00:00",
                    "kind": "virtual",
                    "meeting_provider_id": "zoom",
                    "meeting_recording_published": false,
                    "meeting_recording_url": "https://youtube.com/watch?v=session-override",
                    "meeting_requested": true
                }
            ]
        }'::jsonb
    )$$,
    'Should execute update when automatic session meeting recording override is provided'
);
select is(
    (select meeting_recording_published from session where session_id = :'session1ID'::uuid),
    false,
    'Should persist session recording visibility when unpublished'
);
select is(
    (select meeting_recording_url from session where session_id = :'session1ID'::uuid),
    'https://youtube.com/watch?v=session-override',
    'Should persist session recording override for automatic meetings'
);

-- Should clear session recording override and fall back to synced meeting recording
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000004'::uuid,
        '{
            "name": "Event With Session Pending Sync",
            "description": "Updated event description with cleared session recording override",
            "timezone": "America/New_York",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "starts_at": "2030-04-01T09:00:00",
            "ends_at": "2030-04-01T17:00:00",
            "sessions": [
                {
                    "session_id": "3a3b0000-0000-0000-0000-000000000014",
                    "name": "Session With Pending Sync",
                    "description": "Updated session description with cleared recording override",
                    "starts_at": "2030-04-01T10:00:00",
                    "ends_at": "2030-04-01T11:00:00",
                    "kind": "virtual",
                    "meeting_provider_id": "zoom",
                    "meeting_recording_url": "",
                    "meeting_requested": true
                }
            ]
        }'::jsonb
    )$$,
    'Should execute update when automatic session meeting recording override is cleared'
);
select is(
    (
        with payload as (
            select get_event_full(
                :'alliance1ID'::uuid,
                :'group1ID'::uuid,
                :'event6ID'::uuid
            )::jsonb as event_json
        )
        select session_json->>'meeting_recording_public_url'
        from payload
        cross join lateral jsonb_each(event_json->'sessions') as day(day, sessions)
        cross join lateral jsonb_array_elements(sessions) as session_json
        where session_json->>'session_id' = :'session1ID'
    ),
    null::text,
    'Should keep synced session meeting recording hidden after clearing unpublished override'
);

-- Should keep started synced event automatic meeting archived after meeting setting changes
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000006'::uuid,
        '{
            "name": "Started Synced Event Updated",
            "description": "Updated started synced event description",
            "timezone": "UTC",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "capacity": 100,
            "kind_id": "virtual",
            "meeting_provider_id": "zoom",
            "meeting_recording_requested": false,
            "meeting_requested": true,
            "starts_at": "2020-02-01T10:00:00",
            "ends_at": "2020-02-01T12:00:00"
        }'::jsonb
    )$$,
    'Should execute update for started synced event automatic meeting settings'
);
select is(
    (
        select jsonb_build_object(
            'meeting_in_sync', meeting_in_sync,
            'meeting_recording_requested', meeting_recording_requested,
            'name', name
        )
        from event
        where event_id = :'event25ID'::uuid
    ),
    '{
        "meeting_in_sync": true,
        "meeting_recording_requested": false,
        "name": "Started Synced Event Updated"
    }'::jsonb,
    'Should keep started synced event meeting archived as in sync'
);

-- Should keep started synced session automatic meeting archived after meeting setting changes
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000007'::uuid,
        '{
            "name": "Started Session Parent Event Updated",
            "description": "Updated started session parent description",
            "timezone": "UTC",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "capacity": 100,
            "kind_id": "virtual",
            "meeting_requested": false,
            "starts_at": "2020-02-02T09:00:00",
            "ends_at": "2020-02-02T13:00:00",
            "sessions": [
                {
                    "session_id": "3a3b0000-0000-0000-0000-000000000016",
                    "name": "Started Synced Session Updated",
                    "description": "Updated started synced session description",
                    "starts_at": "2020-02-02T10:00:00",
                    "ends_at": "2020-02-02T11:00:00",
                    "kind": "virtual",
                    "meeting_provider_id": "zoom",
                    "meeting_requested": true
                }
            ]
        }'::jsonb
    )$$,
    'Should execute update for started synced session automatic meeting settings'
);
select is(
    (
        select jsonb_build_object(
            'meeting_in_sync', meeting_in_sync,
            'name', name
        )
        from session
        where session_id = :'session4ID'::uuid
    ),
    '{
        "meeting_in_sync": true,
        "name": "Started Synced Session Updated"
    }'::jsonb,
    'Should keep started synced session meeting archived as in sync'
);

-- Update event without the session (removes it via cascade)
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3b0000-0000-0000-0000-000000000008'::uuid,
        '3a3b0000-0000-0000-0000-000000000005'::uuid,
        '{
            "name": "Event For Session Removal Test",
            "description": "This event has a session with a meeting",
            "timezone": "America/New_York",
            "category_id": "3a3b0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "starts_at": "2030-05-01T09:00:00",
            "ends_at": "2030-05-01T17:00:00",
            "sessions": []
        }'::jsonb
    )$$,
    'Should remove omitted sessions on update'
);

-- Should verify session is deleted and meeting is orphan after update
select is(
    (select count(*) from session where session_id = :'session2ID'),
    0::bigint,
    'Session is deleted after update_event with empty sessions'
);
select is(
    (select jsonb_build_object('meeting_id', meeting_id, 'session_id', session_id) from meeting where meeting_id = :'meeting1ID'),
    jsonb_build_object('meeting_id', :'meeting1ID'::uuid, 'session_id', null),
    'Meeting becomes orphan (session_id set to null) after session deletion'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
