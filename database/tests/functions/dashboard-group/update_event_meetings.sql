-- Tests updating event meeting settings.
-- Split from update_event.sql to keep that file a manageable size.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(27);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '3a3b0000-0000-0000-0000-000000000001'
\set community1ID '3a3b0000-0000-0000-0000-000000000002'
\set event5ID '3a3b0000-0000-0000-0000-000000000003'
\set event5PriceWindowID '3a3b0000-0000-0000-0000-000000000018'
\set event5TicketTypeID '3a3b0000-0000-0000-0000-000000000019'
\set event6ID '3a3b0000-0000-0000-0000-000000000004'
\set event6PriceWindowID '3a3b0000-0000-0000-0000-000000000020'
\set event6TicketTypeID '3a3b0000-0000-0000-0000-000000000021'
\set event7ID '3a3b0000-0000-0000-0000-000000000005'
\set event7PriceWindowID '3a3b0000-0000-0000-0000-000000000022'
\set event7TicketTypeID '3a3b0000-0000-0000-0000-000000000023'
\set event25ID '3a3b0000-0000-0000-0000-000000000006'
\set event25PriceWindowID '3a3b0000-0000-0000-0000-000000000024'
\set event25TicketTypeID '3a3b0000-0000-0000-0000-000000000025'
\set event26ID '3a3b0000-0000-0000-0000-000000000007'
\set event26PriceWindowID '3a3b0000-0000-0000-0000-000000000026'
\set event26TicketTypeID '3a3b0000-0000-0000-0000-000000000027'
\set group1ID '3a3b0000-0000-0000-0000-000000000008'
\set groupCategoryID '3a3b0000-0000-0000-0000-000000000017'
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

-- Baseline communities, group categories, event categories and groups
select fx_community(:'community1ID');
select fx_group_category(:'groupCategoryID', :'community1ID');
select fx_event_category(:'category1ID', :'community1ID');
select fx_group(:'group1ID', :'community1ID', :'groupCategoryID');

-- Event with meeting_in_sync=false for testing preservation
select fx_event(:'event5ID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2030-03-01 12:00:00-05',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'name', 'Event With Pending Sync',
    'published', true,
    'starts_at', '2030-03-01 10:00:00-05',
    'timezone', 'America/New_York'
));

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
select fx_event(:'event25ID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2020-02-01 12:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'name', 'Started Synced Event',
    'published', true,
    'starts_at', '2020-02-01 10:00:00+00'
));

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
select fx_event(:'event6ID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', '2030-04-01 17:00:00-04',
    'event_kind_id', 'virtual',
    'name', 'Event With Session Pending Sync',
    'starts_at', '2030-04-01 09:00:00-04',
    'timezone', 'America/New_York'
));

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
select fx_event(:'event26ID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', '2020-02-02 13:00:00+00',
    'event_kind_id', 'virtual',
    'name', 'Started Session Parent Event',
    'published', true,
    'starts_at', '2020-02-02 09:00:00+00'
));

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
select fx_event(:'event7ID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'This event has a session with a meeting',
    'ends_at', '2030-05-01 17:00:00-04',
    'event_kind_id', 'virtual',
    'name', 'Event For Session Removal Test',
    'published', true,
    'starts_at', '2030-05-01 09:00:00-04',
    'timezone', 'America/New_York'
));

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

-- Free ticket tier for the pending event meeting sync event
select fx_event_ticket_type(:'event5TicketTypeID', :'event5ID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the session pending meeting sync event
select fx_event_ticket_type(:'event6TicketTypeID', :'event6ID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the session removal event
select fx_event_ticket_type(:'event7TicketTypeID', :'event7ID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the started synced event
select fx_event_ticket_type(:'event25TicketTypeID', :'event25ID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the started session parent event
select fx_event_ticket_type(:'event26TicketTypeID', :'event26ID', jsonb_build_object('seats_total', 100));

-- Current free price for the pending event meeting sync tier
select fx_event_ticket_price_window(:'event5PriceWindowID', :'event5TicketTypeID');

-- Current free price for the session pending meeting sync tier
select fx_event_ticket_price_window(:'event6PriceWindowID', :'event6TicketTypeID');

-- Current free price for the session removal tier
select fx_event_ticket_price_window(:'event7PriceWindowID', :'event7TicketTypeID');

-- Current free price for the started synced event tier
select fx_event_ticket_price_window(:'event25PriceWindowID', :'event25TicketTypeID');

-- Current free price for the started session parent event tier
select fx_event_ticket_price_window(:'event26PriceWindowID', :'event26TicketTypeID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject an event meeting longer than the provider maximum duration
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, %L::jsonb)$$,
        :'group1ID',
        :'event5ID',
        jsonb_build_object(
            'capacity', 100,
            'category_id', :'category1ID',
            'description', 'Extended schedule',
            'ends_at', '2030-03-01T22:30:00',
            'kind_id', 'virtual',
            'meeting_provider_id', 'zoom',
            'meeting_requested', true,
            'name', 'Event With Pending Sync',
            'starts_at', '2030-03-01T10:00:00',
            'timezone', 'America/New_York'
        ),
        jsonb_build_object(
            'zoom', jsonb_build_object(
                'max_duration_minutes', 720,
                'max_participants', 100,
                'min_duration_minutes', 5
            )
        )
    ),
    'OCG01',
    'event meeting duration (750 minutes) must be between 5 and 720 minutes',
    'Should reject an event meeting longer than the provider maximum duration'
);

-- Should execute unrelated update with pending event meeting sync
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event5ID',
        jsonb_build_object(
            'capacity', 100,
            'category_id', :'category1ID',
            'description', 'Updated description - unrelated to meeting',
            'ends_at', '2030-03-01T12:00:00',
            'kind_id', 'virtual',
            'meeting_provider_id', 'zoom',
            'meeting_requested', true,
            'name', 'Event With Pending Sync',
            'starts_at', '2030-03-01T10:00:00',
            'timezone', 'America/New_York'
        )
    ),
    'Should execute unrelated update with pending event meeting sync'
);

-- Should keep event meeting_in_sync=false after unrelated update
select is(
    (select meeting_in_sync from event where event_id = :'event5ID'::uuid),
    false,
    'Should keep event meeting_in_sync=false after unrelated update'
);

-- Should execute update when event meeting_requested changes to false
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event5ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Updated description',
            'ends_at', '2030-03-01T12:00:00',
            'kind_id', 'virtual',
            'meeting_requested', false,
            'name', 'Event With Pending Sync',
            'starts_at', '2030-03-01T10:00:00',
            'timezone', 'America/New_York'
        )
    ),
    'Should execute update when event meeting_requested changes to false'
);

-- Should keep event meeting_in_sync=false when meeting_requested changes to false
select is(
    (select meeting_in_sync from event where event_id = :'event5ID'::uuid),
    false,
    'Should keep event meeting_in_sync=false when meeting_requested changes to false'
);

-- Should execute update when automatic event meeting recording override is provided
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event5ID',
        jsonb_build_object(
            'capacity', 100,
            'category_id', :'category1ID',
            'description', 'Updated description with recording override',
            'ends_at', '2030-03-01T12:00:00',
            'kind_id', 'virtual',
            'meeting_provider_id', 'zoom',
            'meeting_recording_published', false,
            'meeting_recording_requested', false,
            'meeting_recording_url', 'https://youtube.com/watch?v=event-override',
            'meeting_requested', true,
            'name', 'Event With Pending Sync',
            'starts_at', '2030-03-01T10:00:00',
            'timezone', 'America/New_York'
        )
    ),
    'Should execute update when automatic event meeting recording override is provided'
);

-- Should persist event recording override for automatic meetings
select is(
    (select meeting_recording_url from event where event_id = :'event5ID'::uuid),
    'https://youtube.com/watch?v=event-override',
    'Should persist event recording override for automatic meetings'
);

-- Should persist event recording visibility when unpublished
select is(
    (select meeting_recording_published from event where event_id = :'event5ID'::uuid),
    false,
    'Should persist event recording visibility when unpublished'
);

-- Should persist event meeting recording preference when disabled
select is(
    (select meeting_recording_requested from event where event_id = :'event5ID'::uuid),
    false,
    'Should persist event meeting recording preference when disabled'
);

-- Should execute update when automatic event meeting recording override is cleared
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event5ID',
        jsonb_build_object(
            'capacity', 100,
            'category_id', :'category1ID',
            'description', 'Updated description with cleared recording override',
            'ends_at', '2030-03-01T12:00:00',
            'kind_id', 'virtual',
            'meeting_provider_id', 'zoom',
            'meeting_recording_url', '',
            'meeting_requested', true,
            'name', 'Event With Pending Sync',
            'starts_at', '2030-03-01T10:00:00',
            'timezone', 'America/New_York'
        )
    ),
    'Should execute update when automatic event meeting recording override is cleared'
);

-- Should keep synced event meeting recording hidden after clearing unpublished override
select is(
    (
        select get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event5ID'::uuid
        )::jsonb->>'meeting_recording_public_url'
    ),
    null::text,
    'Should keep synced event meeting recording hidden after clearing unpublished override'
);

-- Should execute unrelated update with pending session meeting sync
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event6ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Updated event description - unrelated to session meeting',
            'ends_at', '2030-04-01T17:00:00',
            'kind_id', 'virtual',
            'name', 'Event With Session Pending Sync',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'description', 'Updated session description - unrelated to meeting',
                    'ends_at', '2030-04-01T11:00:00',
                    'kind', 'virtual',
                    'meeting_provider_id', 'zoom',
                    'meeting_requested', true,
                    'name', 'Session With Pending Sync',
                    'session_id', :'session1ID',
                    'starts_at', '2030-04-01T10:00:00'
                )
            ),
            'starts_at', '2030-04-01T09:00:00',
            'timezone', 'America/New_York'
        )
    ),
    'Should execute unrelated update with pending session meeting sync'
);

-- Should keep session meeting_in_sync=false after unrelated update
select is(
    (select meeting_in_sync from session where session_id = :'session1ID'::uuid),
    false,
    'Should keep session meeting_in_sync=false after unrelated update'
);

-- Should execute update when session meeting_requested changes to false
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event6ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Updated event description',
            'ends_at', '2030-04-01T17:00:00',
            'kind_id', 'virtual',
            'name', 'Event With Session Pending Sync',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'description', 'Updated session description',
                    'ends_at', '2030-04-01T11:00:00',
                    'kind', 'virtual',
                    'meeting_requested', false,
                    'name', 'Session With Pending Sync',
                    'session_id', :'session1ID',
                    'starts_at', '2030-04-01T10:00:00'
                )
            ),
            'starts_at', '2030-04-01T09:00:00',
            'timezone', 'America/New_York'
        )
    ),
    'Should execute update when session meeting_requested changes to false'
);

-- Should keep session meeting_in_sync=false when meeting_requested changes to false
select is(
    (select meeting_in_sync from session where session_id = :'session1ID'::uuid),
    false,
    'Should keep session meeting_in_sync=false when meeting_requested changes to false'
);

-- Should execute update when automatic session meeting recording override is provided
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event6ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Updated event description with session recording override',
            'ends_at', '2030-04-01T17:00:00',
            'kind_id', 'virtual',
            'name', 'Event With Session Pending Sync',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'description', 'Updated session description with recording override',
                    'ends_at', '2030-04-01T11:00:00',
                    'kind', 'virtual',
                    'meeting_provider_id', 'zoom',
                    'meeting_recording_published', false,
                    'meeting_recording_url', 'https://youtube.com/watch?v=session-override',
                    'meeting_requested', true,
                    'name', 'Session With Pending Sync',
                    'session_id', :'session1ID',
                    'starts_at', '2030-04-01T10:00:00'
                )
            ),
            'starts_at', '2030-04-01T09:00:00',
            'timezone', 'America/New_York'
        )
    ),
    'Should execute update when automatic session meeting recording override is provided'
);

-- Should persist session recording visibility when unpublished
select is(
    (select meeting_recording_published from session where session_id = :'session1ID'::uuid),
    false,
    'Should persist session recording visibility when unpublished'
);

-- Should persist session recording override for automatic meetings
select is(
    (select meeting_recording_url from session where session_id = :'session1ID'::uuid),
    'https://youtube.com/watch?v=session-override',
    'Should persist session recording override for automatic meetings'
);

-- Should execute update when automatic session meeting recording override is cleared
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event6ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Updated event description with cleared session recording override',
            'ends_at', '2030-04-01T17:00:00',
            'kind_id', 'virtual',
            'name', 'Event With Session Pending Sync',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'description', 'Updated session description with cleared recording override',
                    'ends_at', '2030-04-01T11:00:00',
                    'kind', 'virtual',
                    'meeting_provider_id', 'zoom',
                    'meeting_recording_url', '',
                    'meeting_requested', true,
                    'name', 'Session With Pending Sync',
                    'session_id', :'session1ID',
                    'starts_at', '2030-04-01T10:00:00'
                )
            ),
            'starts_at', '2030-04-01T09:00:00',
            'timezone', 'America/New_York'
        )
    ),
    'Should execute update when automatic session meeting recording override is cleared'
);

-- Should keep synced session meeting recording hidden after clearing unpublished override
select is(
    (
        with payload as (
            select get_event_full(
                :'community1ID'::uuid,
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

-- Should execute update for started synced event automatic meeting settings
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event25ID',
        jsonb_build_object(
            'capacity', 100,
            'category_id', :'category1ID',
            'description', 'Updated started synced event description',
            'ends_at', '2020-02-01T12:00:00',
            'kind_id', 'virtual',
            'meeting_provider_id', 'zoom',
            'meeting_recording_requested', false,
            'meeting_requested', true,
            'name', 'Started Synced Event Updated',
            'starts_at', '2020-02-01T10:00:00',
            'timezone', 'UTC'
        )
    ),
    'Should execute update for started synced event automatic meeting settings'
);

-- Should keep started synced event meeting archived as in sync
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

-- Should execute update for started synced session automatic meeting settings
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event26ID',
        jsonb_build_object(
            'capacity', 100,
            'category_id', :'category1ID',
            'description', 'Updated started session parent description',
            'ends_at', '2020-02-02T13:00:00',
            'kind_id', 'virtual',
            'meeting_requested', false,
            'name', 'Started Session Parent Event Updated',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'description', 'Updated started synced session description',
                    'ends_at', '2020-02-02T11:00:00',
                    'kind', 'virtual',
                    'meeting_provider_id', 'zoom',
                    'meeting_requested', true,
                    'name', 'Started Synced Session Updated',
                    'session_id', :'session4ID',
                    'starts_at', '2020-02-02T10:00:00'
                )
            ),
            'starts_at', '2020-02-02T09:00:00',
            'timezone', 'UTC'
        )
    ),
    'Should execute update for started synced session automatic meeting settings'
);

-- Should keep started synced session meeting archived as in sync
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

-- Should remove omitted sessions on update
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event7ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'This event has a session with a meeting',
            'ends_at', '2030-05-01T17:00:00',
            'kind_id', 'virtual',
            'name', 'Event For Session Removal Test',
            'sessions', '[]'::jsonb,
            'starts_at', '2030-05-01T09:00:00',
            'timezone', 'America/New_York'
        )
    ),
    'Should remove omitted sessions on update'
);

-- Should delete the session after update_event receives empty sessions
select is(
    (select count(*) from session where session_id = :'session2ID'),
    0::bigint,
    'Should delete the session after update_event receives empty sessions'
);

-- Should orphan the meeting after session deletion
select is(
    (select jsonb_build_object('meeting_id', meeting_id, 'session_id', session_id) from meeting where meeting_id = :'meeting1ID'),
    jsonb_build_object('meeting_id', :'meeting1ID'::uuid, 'session_id', null),
    'Should orphan the meeting after session deletion'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
