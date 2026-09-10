-- Tests deriving the event meeting sync state from the stored row and an update payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a140000-0000-0000-0000-000000000003'
\set eventCategoryID '3a140000-0000-0000-0000-000000000004'
\set groupCategoryID '3a140000-0000-0000-0000-000000000005'
\set groupID '3a140000-0000-0000-0000-000000000006'
\set hostedEventID '3a140000-0000-0000-0000-000000000007'
\set spokenEventID '3a140000-0000-0000-0000-000000000008'
\set user1ID '3a140000-0000-0000-0000-000000000001'
\set user2ID '3a140000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');

-- Synced meeting event whose host rows are compared with the payload
select fx_event(:'hostedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2025-06-01 11:00:00-04',
    'event_kind_id', 'virtual',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'name', 'Sync Event',
    'starts_at', '2025-06-01 10:00:00-04',
    'timezone', 'America/New_York'
));

-- Synced meeting event whose speaker rows are compared with the payload
select fx_event(:'spokenEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2025-06-01 11:00:00-04',
    'event_kind_id', 'virtual',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'name', 'Sync Event',
    'starts_at', '2025-06-01 10:00:00-04',
    'timezone', 'America/New_York'
));

-- Host of the hosted event
insert into event_host (event_id, user_id)
values (:'hostedEventID', :'user1ID');

-- Speaker of the spoken event
insert into event_speaker (event_id, user_id, featured)
values (:'spokenEventID', :'user1ID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- All fields remain in sync so meeting_in_sync stays true
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    true,
    'Event all fields in sync returns true'
);

-- Sub-second precision in the stored row does not desync a payload with whole seconds
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00.250-04:00",
            "ends_at": "2025-06-01T11:00:00.750-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    true,
    'Event stored sub-second precision keeps sync'
);

-- Meeting disabled after being enabled returns false to trigger deletion
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": false
        }'::jsonb
    ),
    false,
    'Event meeting disabled after being enabled returns false'
);

-- Re-enabling meeting after it was disabled desyncs meeting_in_sync
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00",
            "meeting_requested": false
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    false,
    'Event meeting re-enabled after disable desyncs meeting'
);

-- Missing meeting_requested with previously enabled meeting returns false
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00"
        }'::jsonb
    ),
    false,
    'Event meeting requested missing with previous enabled returns false'
);

-- Missing meeting_requested without a previous meeting returns null
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00"
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00"
        }'::jsonb
    ),
    null::boolean,
    'Event without a meeting before or after returns null'
);

-- Name change causes meeting to be out of sync
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Renamed Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    false,
    'Event name change desyncs meeting'
);

-- Schedule change (start or end) desyncs meeting
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:30:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    false,
    'Event schedule change desyncs meeting'
);

-- Timezone change desyncs meeting
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "Europe/Madrid",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T16:00:00",
            "ends_at": "2025-06-01T17:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    false,
    'Event timezone change desyncs meeting'
);

-- Started synced event changes stay archived instead of creating provider update work
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp - interval '1 hour',
            'meeting_in_sync', true,
            'meeting_recording_requested', true,
            'meeting_requested', true,
            'name', 'Started Event',
            'starts_at', current_timestamp - interval '2 hours',
            'timezone', 'UTC'
        )),
        jsonb_build_object(
            'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'kind_id', 'virtual',
            'meeting_recording_requested', false,
            'meeting_requested', true,
            'name', 'Started Event Updated',
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    ),
    true,
    'Started synced event meeting changes stay in sync'
);

-- Started event meeting disabled after being enabled still triggers deletion
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp - interval '1 hour',
            'meeting_in_sync', true,
            'meeting_requested', true,
            'name', 'Started Event',
            'starts_at', current_timestamp - interval '2 hours',
            'timezone', 'UTC'
        )),
        jsonb_build_object(
            'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'kind_id', 'virtual',
            'meeting_requested', false,
            'name', 'Started Event',
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    ),
    false,
    'Started event meeting disabled after being enabled returns false'
);

-- Started pending event remains out of sync
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp - interval '1 hour',
            'meeting_in_sync', false,
            'meeting_requested', true,
            'name', 'Started Pending Event',
            'starts_at', current_timestamp - interval '2 hours',
            'timezone', 'UTC'
        )),
        jsonb_build_object(
            'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'kind_id', 'virtual',
            'meeting_requested', true,
            'name', 'Started Pending Event Updated',
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    ),
    false,
    'Started pending event meeting stays out of sync'
);

-- Recording preference change desyncs meeting
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00",
            "meeting_recording_requested": true,
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_recording_requested": false,
            "meeting_requested": true
        }'::jsonb
    ),
    false,
    'Event recording preference change desyncs meeting'
);

-- meeting_hosts unchanged keeps sync
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb
    ),
    true,
    'Event meeting_hosts unchanged keeps sync'
);

-- meeting_hosts change desyncs meeting
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "starts_at": "2025-06-01T10:00:00-04:00",
            "ends_at": "2025-06-01T11:00:00-04:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb),
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb
    ),
    false,
    'Event meeting_hosts change desyncs meeting'
);

-- Event hosts unchanged keeps sync
select is(
    is_event_meeting_in_sync(
        (select e from event e where e.event_id = :'hostedEventID'),
        format(
            '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_provider_id": "zoom",
            "meeting_requested": true,
            "hosts": ["%s"]
        }',
            :'user1ID'
        )::jsonb
    ),
    true,
    'Event hosts unchanged keeps sync'
);

-- Event hosts change desyncs meeting
select is(
    is_event_meeting_in_sync(
        (select e from event e where e.event_id = :'hostedEventID'),
        format(
            '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_provider_id": "zoom",
            "meeting_requested": true,
            "hosts": ["%s"]
        }',
            :'user2ID'
        )::jsonb
    ),
    false,
    'Event hosts change desyncs meeting'
);

-- Event speakers change desyncs meeting
select is(
    is_event_meeting_in_sync(
        (select e from event e where e.event_id = :'spokenEventID'),
        format(
            '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_provider_id": "zoom",
            "meeting_requested": true,
            "speakers": [{"user_id": "%s", "featured": false}]
        }',
            :'user2ID'
        )::jsonb
    ),
    false,
    'Event speakers change desyncs meeting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
