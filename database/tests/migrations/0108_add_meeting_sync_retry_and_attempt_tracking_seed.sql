-- Seeds schema-107 events and sessions to verify the 0108 create-attempt and sticky host backfill.

begin;

\set communityID '01080000-0000-0000-0000-000000000001'
\set eventCategoryID '01080000-0000-0000-0000-000000000002'
\set eventClaimedNoMeetingID '01080000-0000-0000-0000-000000000003'
\set eventDisabledAfterErrorID '01080000-0000-0000-0000-000000000012'
\set eventNotRequestedID '01080000-0000-0000-0000-000000000004'
\set eventWithMeetingID '01080000-0000-0000-0000-000000000005'
\set groupCategoryID '01080000-0000-0000-0000-000000000006'
\set groupID '01080000-0000-0000-0000-000000000007'
\set meetingEventID '01080000-0000-0000-0000-000000000008'
\set meetingSessionID '01080000-0000-0000-0000-000000000009'
\set sessionClaimedNoMeetingID '01080000-0000-0000-0000-000000000010'
\set sessionOutOfBoundsID '01080000-0000-0000-0000-000000000013'
\set sessionWithMeetingID '01080000-0000-0000-0000-000000000011'

-- Community hosting the migration fixture
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.test/banner-mobile.png',
    'https://example.test/banner.png',
    'Migration 0108 community',
    'Migration 0108 Community',
    'https://example.test/logo.png',
    'migration-0108-community'
);

-- Event category used by the fixture events
insert into event_category (
    event_category_id,
    community_id,
    name
) values (
    :'eventCategoryID',
    :'communityID',
    'Migration 0108 Event Category'
);

-- Group category used by the fixture group
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'groupCategoryID',
    :'communityID',
    'Migration 0108 Group Category'
);

-- Group owning the fixture events
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Migration 0108 Group',
    'migration-0108-group'
);

-- Requested event without a persisted meeting row and with an active host reservation
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    capacity,
    ends_at,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at,
    starts_at
) values (
    :'eventClaimedNoMeetingID',
    'Requested event without meeting',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Event Claimed No Meeting',
    'event-claimed-no-meeting-0108',
    'UTC',

    100,
    '2030-06-01 11:00:00+00',
    false,
    'event-inflight-host@example.test',
    'zoom',
    true,
    '2030-05-01 09:00:00+00',
    '2030-06-01 10:00:00+00'
);

-- Event that never requested an automatic meeting
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    ends_at,
    starts_at
) values (
    :'eventNotRequestedID',
    'Event without meeting request',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Event Not Requested',
    'event-not-requested-0108',
    'UTC',

    '2030-06-02 11:00:00+00',
    '2030-06-02 10:00:00+00'
);

-- Requested event that already has a persisted meeting row
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    capacity,
    ends_at,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    starts_at
) values (
    :'eventWithMeetingID',
    'Requested event with meeting',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Event With Meeting',
    'event-with-meeting-0108',
    'UTC',

    100,
    '2030-06-03 11:00:00+00',
    true,
    'zoom',
    true,
    '2030-06-03 10:00:00+00'
);

-- Event whose meeting request was disabled after an earlier unknown sync timeout
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    capacity,
    ends_at,
    meeting_error,
    meeting_in_sync,
    meeting_requested,
    starts_at
) values (
    :'eventDisabledAfterErrorID',
    'Disabled event after ambiguous timeout',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Event Disabled After Error',
    'event-disabled-after-error-0108',
    'UTC',

    100,
    '2030-06-04 11:00:00+00',
    'meeting synchronization outcome unknown after processing timeout',
    true,
    false,
    '2030-06-04 10:00:00+00'
);

-- Requested session without a persisted meeting row and with an active host reservation
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,

    ends_at,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at
) values (
    :'sessionClaimedNoMeetingID',
    :'eventClaimedNoMeetingID',
    'Session Claimed No Meeting',
    'virtual',
    '2030-06-01 10:00:00+00',

    '2030-06-01 10:30:00+00',
    false,
    'session-inflight-host@example.test',
    'zoom',
    true,
    '2030-05-01 09:00:00+00'
);

-- Requested session that already has a persisted meeting row
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
    :'sessionWithMeetingID',
    :'eventWithMeetingID',
    'Session With Meeting',
    'virtual',
    '2030-06-03 10:00:00+00',

    '2030-06-03 10:30:00+00',
    true,
    'zoom',
    true
);

-- Live session bounds trigger body, which honors the legacy import bypass
\ir ../../migrations/functions/triggers/check_session_within_event_bounds.sql

-- Legacy imported requested session outside its parent event time bounds
select set_config('ocg.skip_session_bounds_check', 'on', true);
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
    :'sessionOutOfBoundsID',
    :'eventClaimedNoMeetingID',
    'Legacy Out Of Bounds Session',
    'virtual',
    '2030-06-01 08:00:00+00',

    '2030-06-01 08:30:00+00',
    false,
    'zoom',
    true
);
select set_config('ocg.skip_session_bounds_check', 'off', true);

-- Persisted meetings linked to the already-provisioned event and session
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    event_id,
    session_id
) values
    (
        :'meetingEventID',
        'https://zoom.us/j/migration-0108-event',
        'zoom',
        'migration-0108-event',

        :'eventWithMeetingID',
        null
    ),
    (
        :'meetingSessionID',
        'https://zoom.us/j/migration-0108-session',
        'zoom',
        'migration-0108-session',

        null,
        :'sessionWithMeetingID'
    );

commit;
