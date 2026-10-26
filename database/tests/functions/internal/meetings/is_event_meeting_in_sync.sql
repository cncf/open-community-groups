-- Tests deriving the event meeting sync state from the stored row and an update payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a140000-0000-0000-0000-000000000003'
\set eventCategoryID '3a140000-0000-0000-0000-000000000004'
\set groupCategoryID '3a140000-0000-0000-0000-000000000005'
\set groupID '3a140000-0000-0000-0000-000000000006'
\set hostedEventID '3a140000-0000-0000-0000-000000000007'
\set localFormat 'YYYY-MM-DD"T"HH24:MI:SS'
\set spokenEventID '3a140000-0000-0000-0000-000000000008'
\set user1ID '3a140000-0000-0000-0000-000000000001'
\set user2ID '3a140000-0000-0000-0000-000000000002'

-- Future whole-second schedule, so the started guard never applies to the base row
select
    date_trunc('day', current_timestamp) + interval '30 days 11 hours' as "endsAt",
    date_trunc('day', current_timestamp) + interval '30 days 10 hours' as "startsAt"
\gset

-- Synced meeting row and the matching update payload that scenarios patch
select
    jsonb_build_object(
        'ends_at', :'endsAt'::timestamptz,
        'meeting_in_sync', true,
        'meeting_provider_id', 'zoom',
        'meeting_recording_requested', true,
        'meeting_requested', true,
        'name', 'Sync Event',
        'starts_at', :'startsAt'::timestamptz,
        'timezone', 'America/New_York'
    ) as "baseBefore",
    jsonb_build_object(
        'ends_at', to_char(:'endsAt'::timestamptz at time zone 'America/New_York', :'localFormat'),
        'meeting_provider_id', 'zoom',
        'meeting_recording_requested', true,
        'meeting_requested', true,
        'name', 'Sync Event',
        'starts_at', to_char(:'startsAt'::timestamptz at time zone 'America/New_York', :'localFormat'),
        'timezone', 'America/New_York'
    ) as "baseAfter"
\gset

-- Synced meeting row that already started and the matching update payload
select
    :'baseBefore'::jsonb || jsonb_build_object(
        'ends_at', current_timestamp - interval '1 hour',
        'starts_at', current_timestamp - interval '2 hours'
    ) as "startedBefore",
    :'baseAfter'::jsonb || jsonb_build_object(
        'ends_at', to_char((current_timestamp - interval '1 hour') at time zone 'America/New_York', :'localFormat'),
        'starts_at', to_char((current_timestamp - interval '2 hours') at time zone 'America/New_York', :'localFormat')
    ) as "startedAfter"
\gset

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
select fx_event(
    :'hostedEventID',
    :'groupID',
    :'eventCategoryID',
    :'baseBefore'::jsonb || '{"capacity": 100, "event_kind_id": "virtual"}'::jsonb
);

-- Synced meeting event whose speaker rows are compared with the payload
select fx_event(
    :'spokenEventID',
    :'groupID',
    :'eventCategoryID',
    :'baseBefore'::jsonb || '{"capacity": 100, "event_kind_id": "virtual"}'::jsonb
);

-- Host of the hosted event
insert into event_host (event_id, user_id)
values (:'hostedEventID', :'user1ID');

-- Speaker of the spoken event
insert into event_speaker (event_id, user_id, featured)
values (:'spokenEventID', :'user1ID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should desync when the end time changes
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb),
        :'baseAfter'::jsonb || jsonb_build_object(
            'ends_at', to_char((:'endsAt'::timestamptz + interval '30 minutes') at time zone 'America/New_York', :'localFormat')
        )
    ),
    false,
    'Should desync when the end time changes'
);

-- Should desync when the hosts change
select is(
    is_event_meeting_in_sync(
        (select e from event e where e.event_id = :'hostedEventID'),
        :'baseAfter'::jsonb || jsonb_build_object('hosts', jsonb_build_array(:'user2ID'))
    ),
    false,
    'Should desync when the hosts change'
);

-- Should desync when the meeting is re-enabled
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(
            null::event,
            :'baseBefore'::jsonb || '{"meeting_in_sync": null, "meeting_requested": false}'::jsonb
        ),
        :'baseAfter'::jsonb
    ),
    false,
    'Should desync when the meeting is re-enabled'
);

-- Should desync when the meeting provider changes
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb),
        :'baseAfter'::jsonb || '{"meeting_provider_id": null}'::jsonb
    ),
    false,
    'Should desync when the meeting provider changes'
);

-- Should desync when the meeting_hosts change
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(
            null::event,
            :'baseBefore'::jsonb || '{"meeting_hosts": ["host1@example.com"]}'::jsonb
        ),
        :'baseAfter'::jsonb || '{"meeting_hosts": ["host1@example.com", "host2@example.com"]}'::jsonb
    ),
    false,
    'Should desync when the meeting_hosts change'
);

-- Should desync when the name changes
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb),
        :'baseAfter'::jsonb || '{"name": "Renamed Event"}'::jsonb
    ),
    false,
    'Should desync when the name changes'
);

-- Should desync when the recording preference changes
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb),
        :'baseAfter'::jsonb || '{"meeting_recording_requested": false}'::jsonb
    ),
    false,
    'Should desync when the recording preference changes'
);

-- Should desync when the speakers change
select is(
    is_event_meeting_in_sync(
        (select e from event e where e.event_id = :'spokenEventID'),
        :'baseAfter'::jsonb || jsonb_build_object(
            'speakers', jsonb_build_array(jsonb_build_object('featured', false, 'user_id', :'user2ID'))
        )
    ),
    false,
    'Should desync when the speakers change'
);

-- Should desync when the start time changes
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb),
        :'baseAfter'::jsonb || jsonb_build_object(
            'starts_at', to_char((:'startsAt'::timestamptz + interval '30 minutes') at time zone 'America/New_York', :'localFormat')
        )
    ),
    false,
    'Should desync when the start time changes'
);

-- Should desync when the timezone changes
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb),
        :'baseAfter'::jsonb || jsonb_build_object(
            'ends_at', to_char(:'endsAt'::timestamptz at time zone 'Europe/Madrid', :'localFormat'),
            'starts_at', to_char(:'startsAt'::timestamptz at time zone 'Europe/Madrid', :'localFormat'),
            'timezone', 'Europe/Madrid'
        )
    ),
    false,
    'Should desync when the timezone changes'
);

-- Should keep a started pending meeting out of sync
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'startedBefore'::jsonb || '{"meeting_in_sync": false}'::jsonb),
        :'startedAfter'::jsonb
    ),
    false,
    'Should keep a started pending meeting out of sync'
);

-- Should keep a started synced meeting in sync when its fields change
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'startedBefore'::jsonb),
        :'startedAfter'::jsonb || '{"meeting_recording_requested": false, "name": "Renamed Event"}'::jsonb
    ),
    true,
    'Should keep a started synced meeting in sync when its fields change'
);

-- Should keep sync when every field is unchanged
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb),
        :'baseAfter'::jsonb
    ),
    true,
    'Should keep sync when every field is unchanged'
);

-- Should keep sync when the hosts are unchanged
select is(
    is_event_meeting_in_sync(
        (select e from event e where e.event_id = :'hostedEventID'),
        :'baseAfter'::jsonb || jsonb_build_object('hosts', jsonb_build_array(:'user1ID'))
    ),
    true,
    'Should keep sync when the hosts are unchanged'
);

-- Should keep sync when the meeting_hosts are unchanged
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(
            null::event,
            :'baseBefore'::jsonb || '{"meeting_hosts": ["host1@example.com", "host2@example.com"]}'::jsonb
        ),
        :'baseAfter'::jsonb || '{"meeting_hosts": ["host1@example.com", "host2@example.com"]}'::jsonb
    ),
    true,
    'Should keep sync when the meeting_hosts are unchanged'
);

-- Should keep sync when the speakers are unchanged
select is(
    is_event_meeting_in_sync(
        (select e from event e where e.event_id = :'spokenEventID'),
        :'baseAfter'::jsonb || jsonb_build_object(
            'speakers', jsonb_build_array(jsonb_build_object('featured', false, 'user_id', :'user1ID'))
        )
    ),
    true,
    'Should keep sync when the speakers are unchanged'
);

-- Should keep sync when the stored times carry sub-second precision
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb || jsonb_build_object(
            'ends_at', :'endsAt'::timestamptz + interval '750 milliseconds',
            'starts_at', :'startsAt'::timestamptz + interval '250 milliseconds'
        )),
        :'baseAfter'::jsonb
    ),
    true,
    'Should keep sync when the stored times carry sub-second precision'
);

-- Should return false when a requested meeting is no longer requested
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb),
        :'baseAfter'::jsonb || '{"meeting_requested": false}'::jsonb
    ),
    false,
    'Should return false when a requested meeting is no longer requested'
);

-- Should return false when a started meeting is no longer requested
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'startedBefore'::jsonb),
        :'startedAfter'::jsonb || '{"meeting_requested": false}'::jsonb
    ),
    false,
    'Should return false when a started meeting is no longer requested'
);

-- Should return false when meeting_requested is missing after a requested meeting
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb),
        :'baseAfter'::jsonb - 'meeting_requested'
    ),
    false,
    'Should return false when meeting_requested is missing after a requested meeting'
);

-- Should return null when no meeting is requested before or after
select is(
    is_event_meeting_in_sync(
        jsonb_populate_record(null::event, :'baseBefore'::jsonb - 'meeting_in_sync' - 'meeting_requested'),
        :'baseAfter'::jsonb - 'meeting_requested'
    ),
    null::boolean,
    'Should return null when no meeting is requested before or after'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
