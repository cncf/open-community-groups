-- Tests deriving the session meeting sync state from the stored rows and an update payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(23);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a150000-0000-0000-0000-000000000003'
\set eventCategoryID '3a150000-0000-0000-0000-000000000004'
\set groupCategoryID '3a150000-0000-0000-0000-000000000005'
\set groupID '3a150000-0000-0000-0000-000000000006'
\set hostedEventID '3a150000-0000-0000-0000-000000000007'
\set hostedSessionID '3a150000-0000-0000-0000-000000000008'
\set localFormat 'YYYY-MM-DD"T"HH24:MI:SS'
\set spokenEventID '3a150000-0000-0000-0000-000000000009'
\set spokenSessionID '3a150000-0000-0000-0000-000000000010'
\set user1ID '3a150000-0000-0000-0000-000000000001'
\set user2ID '3a150000-0000-0000-0000-000000000002'

-- Future whole-second schedules, so the started guard never applies to the base rows
select
    date_trunc('day', current_timestamp) + interval '30 days 11 hours' as "eventEndsAt",
    date_trunc('day', current_timestamp) + interval '30 days 10 hours' as "eventStartsAt",
    date_trunc('day', current_timestamp) + interval '30 days 10 hours 45 minutes' as "sessionEndsAt",
    date_trunc('day', current_timestamp) + interval '30 days 10 hours 15 minutes' as "sessionStartsAt"
\gset

-- Synced meeting rows and the matching update payloads that scenarios patch
select
    jsonb_build_object(
        'meeting_recording_requested', true,
        'timezone', 'America/New_York'
    ) as "baseEventBefore",
    jsonb_build_object(
        'meeting_recording_requested', true,
        'timezone', 'America/New_York'
    ) as "baseEventAfter",
    jsonb_build_object(
        'ends_at', :'sessionEndsAt'::timestamptz,
        'meeting_in_sync', true,
        'meeting_provider_id', 'zoom',
        'meeting_requested', true,
        'name', 'Session One',
        'session_kind_id', 'virtual',
        'starts_at', :'sessionStartsAt'::timestamptz
    ) as "baseSessionBefore",
    jsonb_build_object(
        'ends_at', to_char(:'sessionEndsAt'::timestamptz at time zone 'America/New_York', :'localFormat'),
        'kind', 'virtual',
        'meeting_provider_id', 'zoom',
        'meeting_requested', true,
        'name', 'Session One',
        'starts_at', to_char(:'sessionStartsAt'::timestamptz at time zone 'America/New_York', :'localFormat')
    ) as "baseSessionAfter"
\gset

-- Synced session meeting row that already started and the matching update payload
select
    :'baseSessionBefore'::jsonb || jsonb_build_object(
        'ends_at', current_timestamp - interval '1 hour',
        'starts_at', current_timestamp - interval '2 hours'
    ) as "startedSessionBefore",
    :'baseSessionAfter'::jsonb || jsonb_build_object(
        'ends_at', to_char((current_timestamp - interval '1 hour') at time zone 'America/New_York', :'localFormat'),
        'starts_at', to_char((current_timestamp - interval '2 hours') at time zone 'America/New_York', :'localFormat')
    ) as "startedSessionAfter"
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

-- Event whose host rows are compared with the payload
select fx_event(
    :'hostedEventID',
    :'groupID',
    :'eventCategoryID',
    :'baseEventBefore'::jsonb || jsonb_build_object(
        'ends_at', :'eventEndsAt'::timestamptz,
        'event_kind_id', 'virtual',
        'starts_at', :'eventStartsAt'::timestamptz
    )
);

-- Event whose session speaker rows are compared with the payload
select fx_event(
    :'spokenEventID',
    :'groupID',
    :'eventCategoryID',
    :'baseEventBefore'::jsonb || jsonb_build_object(
        'ends_at', :'eventEndsAt'::timestamptz,
        'event_kind_id', 'virtual',
        'starts_at', :'eventStartsAt'::timestamptz
    )
);

-- Host of the hosted event
insert into event_host (event_id, user_id)
values (:'hostedEventID', :'user1ID');

-- Synced meeting session of the hosted event
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'hostedSessionID',
    :'hostedEventID',
    'Session One',
    'virtual',
    :'sessionStartsAt',
    :'sessionEndsAt',
    true,
    'zoom',
    true
);

-- Synced meeting session of the spoken event
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'spokenSessionID',
    :'spokenEventID',
    'Session One',
    'virtual',
    :'sessionStartsAt',
    :'sessionEndsAt',
    true,
    'zoom',
    true
);

-- Speaker of the spoken session
insert into session_speaker (session_id, user_id, featured)
values (:'spokenSessionID', :'user1ID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should desync when the end time changes
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb),
        :'baseSessionAfter'::jsonb || jsonb_build_object(
            'ends_at', to_char((:'sessionEndsAt'::timestamptz + interval '15 minutes') at time zone 'America/New_York', :'localFormat')
        ),
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should desync when the end time changes'
);

-- Should desync when the event hosts change
select is(
    is_session_meeting_in_sync(
        (select s from session s where s.session_id = :'hostedSessionID'),
        :'baseSessionAfter'::jsonb,
        (select e from event e where e.event_id = :'hostedEventID'),
        :'baseEventAfter'::jsonb || jsonb_build_object('hosts', jsonb_build_array(:'user2ID'))
    ),
    false,
    'Should desync when the event hosts change'
);

-- Should desync when the event recording preference changes
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb),
        :'baseSessionAfter'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb || '{"meeting_recording_requested": false}'::jsonb
    ),
    false,
    'Should desync when the event recording preference changes'
);

-- Should desync when the event timezone changes
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb),
        :'baseSessionAfter'::jsonb || jsonb_build_object(
            'ends_at', to_char(:'sessionEndsAt'::timestamptz at time zone 'Europe/Madrid', :'localFormat'),
            'starts_at', to_char(:'sessionStartsAt'::timestamptz at time zone 'Europe/Madrid', :'localFormat')
        ),
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb || '{"timezone": "Europe/Madrid"}'::jsonb
    ),
    false,
    'Should desync when the event timezone changes'
);

-- Should desync when the kind changes from hybrid to in-person
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb || '{"session_kind_id": "hybrid"}'::jsonb),
        :'baseSessionAfter'::jsonb || '{"kind": "in-person"}'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should desync when the kind changes from hybrid to in-person'
);

-- Should desync when the kind changes from virtual to in-person
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb),
        :'baseSessionAfter'::jsonb || '{"kind": "in-person"}'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should desync when the kind changes from virtual to in-person'
);

-- Should desync when the meeting is re-enabled
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(
            null::session,
            :'baseSessionBefore'::jsonb || '{"meeting_in_sync": null, "meeting_requested": false}'::jsonb
        ),
        :'baseSessionAfter'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should desync when the meeting is re-enabled'
);

-- Should desync when the meeting provider changes
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb),
        :'baseSessionAfter'::jsonb || '{"meeting_provider_id": null}'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should desync when the meeting provider changes'
);

-- Should desync when the meeting_hosts change
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(
            null::session,
            :'baseSessionBefore'::jsonb || '{"meeting_hosts": ["host1@example.com"]}'::jsonb
        ),
        :'baseSessionAfter'::jsonb || '{"meeting_hosts": ["host1@example.com", "host2@example.com"]}'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should desync when the meeting_hosts change'
);

-- Should desync when the name changes
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb),
        :'baseSessionAfter'::jsonb || '{"name": "Renamed Session"}'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should desync when the name changes'
);

-- Should desync when the speakers change
select is(
    is_session_meeting_in_sync(
        (select s from session s where s.session_id = :'spokenSessionID'),
        :'baseSessionAfter'::jsonb || jsonb_build_object(
            'speakers', jsonb_build_array(jsonb_build_object('featured', false, 'user_id', :'user2ID'))
        ),
        (select e from event e where e.event_id = :'spokenEventID'),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should desync when the speakers change'
);

-- Should desync when the start time changes
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb),
        :'baseSessionAfter'::jsonb || jsonb_build_object(
            'starts_at', to_char((:'sessionStartsAt'::timestamptz - interval '15 minutes') at time zone 'America/New_York', :'localFormat')
        ),
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should desync when the start time changes'
);

-- Should keep a started pending meeting out of sync
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(
            null::session,
            :'startedSessionBefore'::jsonb || '{"meeting_in_sync": false}'::jsonb
        ),
        :'startedSessionAfter'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should keep a started pending meeting out of sync'
);

-- Should keep a started synced meeting in sync when its fields change
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'startedSessionBefore'::jsonb),
        :'startedSessionAfter'::jsonb || '{"name": "Renamed Session"}'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb || '{"meeting_recording_requested": false}'::jsonb
    ),
    true,
    'Should keep a started synced meeting in sync when its fields change'
);

-- Should keep sync when every field is unchanged
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb),
        :'baseSessionAfter'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    true,
    'Should keep sync when every field is unchanged'
);

-- Should keep sync when the event hosts are unchanged
select is(
    is_session_meeting_in_sync(
        (select s from session s where s.session_id = :'hostedSessionID'),
        :'baseSessionAfter'::jsonb,
        (select e from event e where e.event_id = :'hostedEventID'),
        :'baseEventAfter'::jsonb || jsonb_build_object('hosts', jsonb_build_array(:'user1ID'))
    ),
    true,
    'Should keep sync when the event hosts are unchanged'
);

-- Should keep sync when the meeting_hosts are unchanged
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(
            null::session,
            :'baseSessionBefore'::jsonb || '{"meeting_hosts": ["host1@example.com", "host2@example.com"]}'::jsonb
        ),
        :'baseSessionAfter'::jsonb || '{"meeting_hosts": ["host1@example.com", "host2@example.com"]}'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    true,
    'Should keep sync when the meeting_hosts are unchanged'
);

-- Should keep sync when the speakers are unchanged
select is(
    is_session_meeting_in_sync(
        (select s from session s where s.session_id = :'spokenSessionID'),
        :'baseSessionAfter'::jsonb || jsonb_build_object(
            'speakers', jsonb_build_array(jsonb_build_object('featured', false, 'user_id', :'user1ID'))
        ),
        (select e from event e where e.event_id = :'spokenEventID'),
        :'baseEventAfter'::jsonb
    ),
    true,
    'Should keep sync when the speakers are unchanged'
);

-- Should keep sync when the stored times carry sub-second precision
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb || jsonb_build_object(
            'ends_at', :'sessionEndsAt'::timestamptz + interval '750 milliseconds',
            'starts_at', :'sessionStartsAt'::timestamptz + interval '250 milliseconds'
        )),
        :'baseSessionAfter'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    true,
    'Should keep sync when the stored times carry sub-second precision'
);

-- Should return false when a requested meeting is no longer requested
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb),
        :'baseSessionAfter'::jsonb || '{"meeting_requested": false}'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should return false when a requested meeting is no longer requested'
);

-- Should return false when a started meeting is no longer requested
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'startedSessionBefore'::jsonb),
        :'startedSessionAfter'::jsonb || '{"meeting_requested": false}'::jsonb,
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should return false when a started meeting is no longer requested'
);

-- Should return false when meeting_requested is missing after a requested meeting
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, :'baseSessionBefore'::jsonb),
        :'baseSessionAfter'::jsonb - 'meeting_requested',
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    false,
    'Should return false when meeting_requested is missing after a requested meeting'
);

-- Should return null when no meeting is requested before or after
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(
            null::session,
            :'baseSessionBefore'::jsonb - 'meeting_in_sync' - 'meeting_requested'
        ),
        :'baseSessionAfter'::jsonb - 'meeting_requested',
        jsonb_populate_record(null::event, :'baseEventBefore'::jsonb),
        :'baseEventAfter'::jsonb
    ),
    null::boolean,
    'Should return null when no meeting is requested before or after'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
