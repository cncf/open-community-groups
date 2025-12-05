-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(28);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000002'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'

\set eventCreateID '00000000-0000-0000-0000-000000000101'
\set eventDeleteCanceledID '00000000-0000-0000-0000-000000000103'
\set eventDeleteSoftID '00000000-0000-0000-0000-000000000104'
\set eventInSyncID '00000000-0000-0000-0000-000000000105'
\set eventMeetingDisabledID '00000000-0000-0000-0000-000000000114'
\set eventNoMeetingID '00000000-0000-0000-0000-000000000106'
\set eventOrphanID '00000000-0000-0000-0000-000000000107'
\set eventOrphanWithSessionID '00000000-0000-0000-0000-000000000108'
\set eventRequiresPasswordID '00000000-0000-0000-0000-000000000110'
\set eventSessionOrphanID '00000000-0000-0000-0000-000000000109'
\set eventUnpublishedCreateID '00000000-0000-0000-0000-000000000111'
\set eventUnpublishedDeleteID '00000000-0000-0000-0000-000000000112'
\set eventUnpublishedSessionID '00000000-0000-0000-0000-000000000113'
\set eventUpdateID '00000000-0000-0000-0000-000000000102'
\set eventCanceledNoMeetingID '00000000-0000-0000-0000-000000000115'
\set sessionCanceledNoMeetingID '00000000-0000-0000-0000-000000000211'

\set sessionCreateID '00000000-0000-0000-0000-000000000201'
\set sessionDeleteParentCanceledID '00000000-0000-0000-0000-000000000203'
\set sessionDeleteParentDeletedID '00000000-0000-0000-0000-000000000204'
\set sessionInSyncID '00000000-0000-0000-0000-000000000205'
\set sessionMeetingDisabledID '00000000-0000-0000-0000-000000000210'
\set sessionOrphanCascadeID '00000000-0000-0000-0000-000000000207'
\set sessionOrphanID '00000000-0000-0000-0000-000000000206'
\set sessionRequiresPasswordID '00000000-0000-0000-0000-000000000212'
\set sessionUnpublishedCreateID '00000000-0000-0000-0000-000000000208'
\set sessionUnpublishedDeleteID '00000000-0000-0000-0000-000000000209'
\set sessionUpdateID '00000000-0000-0000-0000-000000000202'

\set meetingEventDeleteCanceledID '00000000-0000-0000-0000-000000000302'
\set meetingEventDeleteSoftID '00000000-0000-0000-0000-000000000303'
\set meetingEventMeetingDisabledID '00000000-0000-0000-0000-000000000313'
\set meetingEventUnpublishedDeleteID '00000000-0000-0000-0000-000000000311'
\set meetingEventUpdateID '00000000-0000-0000-0000-000000000301'
\set meetingOrphanEventCascadeID '00000000-0000-0000-0000-000000000309'
\set meetingOrphanEventID '00000000-0000-0000-0000-000000000307'
\set meetingOrphanSessionCascadeID '00000000-0000-0000-0000-000000000310'
\set meetingOrphanSessionID '00000000-0000-0000-0000-000000000308'
\set meetingSessionDeleteParentCanceledID '00000000-0000-0000-0000-000000000305'
\set meetingSessionDeleteParentDeletedID '00000000-0000-0000-0000-000000000306'
\set meetingSessionMeetingDisabledID '00000000-0000-0000-0000-000000000314'
\set meetingSessionUnpublishedDeleteID '00000000-0000-0000-0000-000000000312'
\set meetingSessionUpdateID '00000000-0000-0000-0000-000000000304'

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

-- Event: needs meeting create (published, meeting_requested=true, meeting_in_sync=false, no meeting row)
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
    meeting_hosts,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    published
) values (
    :'eventCreateID',
    :'groupID',
    'Event Create Test',
    'event-create-test',
    'Test event for meeting create',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-01 10:00:00-04',
    '2025-06-01 11:00:00-04',
    array['host1@example.com', 'host2@example.com'],
    false,
    'zoom',
    true,
    true
);

-- Event: needs meeting update (published, meeting_requested=true, meeting_in_sync=false, has meeting row)
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
    meeting_requested,
    published
) values (
    :'eventUpdateID',
    :'groupID',
    'Event Update Test',
    'event-update-test',
    'Test event for meeting update',
    'America/Chicago',
    :'categoryID',
    'virtual',
    '2025-06-02 10:00:00-05',
    '2025-06-02 12:00:00-05',
    false,
    'zoom',
    true,
    true
);
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url, password)
values (:'meetingEventUpdateID', :'eventUpdateID', 'zoom', '123456789', 'https://zoom.us/j/123456789', 'pass123');

-- Event: needs meeting delete (canceled)
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

    canceled,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'eventDeleteCanceledID',
    :'groupID',
    'Event Delete Canceled Test',
    'event-delete-canceled-test',
    'Test event for meeting delete (canceled)',
    'America/Los_Angeles',
    :'categoryID',
    'virtual',
    '2025-06-03 10:00:00-07',
    '2025-06-03 11:00:00-07',

    true,
    false,
    'zoom',
    true
);
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingEventDeleteCanceledID', :'eventDeleteCanceledID', 'zoom', '987654321', 'https://zoom.us/j/987654321');

-- Event: needs meeting delete (soft deleted)
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

    deleted,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'eventDeleteSoftID',
    :'groupID',
    'Event Delete Soft Test',
    'event-delete-soft-test',
    'Test event for meeting delete (soft deleted)',
    'Europe/London',
    :'categoryID',
    'virtual',
    '2025-06-04 10:00:00+01',
    '2025-06-04 11:00:00+01',

    true,
    false,
    'zoom',
    true
);
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingEventDeleteSoftID', :'eventDeleteSoftID', 'zoom', '111222333', 'https://zoom.us/j/111222333');

-- Event: in sync (should NOT be returned, but has sessions that need sync)
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
    meeting_requested,
    published
) values (
    :'eventInSyncID',
    :'groupID',
    'Event In Sync Test',
    'event-in-sync-test',
    'Test event already in sync',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-05 10:00:00-04',
    '2025-06-05 11:00:00-04',
    true,
    'zoom',
    true,
    true
);

-- Event: no meeting requested (should NOT be returned)
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
    meeting_requested,
    meeting_in_sync
) values (
    :'eventNoMeetingID',
    :'groupID',
    'Event No Meeting Test',
    'event-no-meeting-test',
    'Test event with no meeting requested',
    'America/New_York',
    :'categoryID',
    'in-person',
    '2025-06-06 10:00:00-04',
    '2025-06-06 11:00:00-04',
    false,
    null
);

-- Session: needs meeting create (on eventInSyncID which is active)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_hosts,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionCreateID',
    :'eventInSyncID',
    'Session Create Test',
    '2025-06-05 10:00:00-04',
    '2025-06-05 10:30:00-04',
    'virtual',
    array['sessionhost@example.com'],
    false,
    'zoom',
    true
);

-- Session: needs meeting update (on eventInSyncID which is active)
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
    :'sessionUpdateID',
    :'eventInSyncID',
    'Session Update Test',
    '2025-06-05 10:30:00-04',
    '2025-06-05 11:00:00-04',
    'virtual',
    false,
    'zoom',
    true
);
insert into meeting (meeting_id, session_id, meeting_provider_id, provider_meeting_id, join_url, password)
values (:'meetingSessionUpdateID', :'sessionUpdateID', 'zoom', '444555666', 'https://zoom.us/j/444555666', 'sesspass');

-- Session: needs meeting delete (parent event canceled)
-- meeting_in_sync=false to be picked up for deletion
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
    :'sessionDeleteParentCanceledID',
    :'eventDeleteCanceledID',
    'Session Delete Parent Canceled Test',
    '2025-06-03 10:00:00-07',
    '2025-06-03 10:30:00-07',
    'virtual',
    false,
    'zoom',
    true
);
insert into meeting (meeting_id, session_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingSessionDeleteParentCanceledID', :'sessionDeleteParentCanceledID', 'zoom', '777888999', 'https://zoom.us/j/777888999');

-- Session: needs meeting delete (parent event deleted)
-- meeting_in_sync=false to be picked up for deletion
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
    :'sessionDeleteParentDeletedID',
    :'eventDeleteSoftID',
    'Session Delete Parent Deleted Test',
    '2025-06-04 10:00:00+01',
    '2025-06-04 10:30:00+01',
    'virtual',
    false,
    'zoom',
    true
);
insert into meeting (meeting_id, session_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingSessionDeleteParentDeletedID', :'sessionDeleteParentDeletedID', 'zoom', '000111222', 'https://zoom.us/j/000111222');

-- Session: in sync (should NOT be returned)
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
    :'sessionInSyncID',
    :'eventInSyncID',
    'Session In Sync Test',
    '2025-06-05 11:00:00-04',
    '2025-06-05 11:30:00-04',
    'virtual',
    true,
    'zoom',
    true
);

-- Event: for orphan test A (event meeting becomes orphan when event is hard deleted)
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
    meeting_requested,
    published
) values (
    :'eventOrphanID',
    :'groupID',
    'Event Orphan Test',
    'event-orphan-test',
    'Test event for orphan meeting',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-07 10:00:00-04',
    '2025-06-07 11:00:00-04',
    true,
    'zoom',
    true,
    true
);
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingOrphanEventID', :'eventOrphanID', 'zoom', '333444555', 'https://zoom.us/j/333444555');

-- Event: for orphan test B (session meeting becomes orphan when session is hard deleted)
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
    meeting_requested,
    meeting_in_sync,
    published
) values (
    :'eventSessionOrphanID',
    :'groupID',
    'Event Session Orphan Test',
    'event-session-orphan-test',
    'Test event for session orphan meeting',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-08 10:00:00-04',
    '2025-06-08 11:00:00-04',
    false,
    null,
    true
);
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
    :'sessionOrphanID',
    :'eventSessionOrphanID',
    'Session Orphan Test',
    '2025-06-08 10:00:00-04',
    '2025-06-08 10:30:00-04',
    'virtual',
    true,
    'zoom',
    true
);
insert into meeting (meeting_id, session_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingOrphanSessionID', :'sessionOrphanID', 'zoom', '666777888', 'https://zoom.us/j/666777888');

-- Event: for orphan test C (both event and session meetings become orphans via cascade)
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
    meeting_requested,
    published
) values (
    :'eventOrphanWithSessionID',
    :'groupID',
    'Event Orphan Cascade Test',
    'event-orphan-cascade-test',
    'Test event for cascade orphan meetings',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-09 10:00:00-04',
    '2025-06-09 11:00:00-04',
    true,
    'zoom',
    true,
    true
);
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingOrphanEventCascadeID', :'eventOrphanWithSessionID', 'zoom', '999000111', 'https://zoom.us/j/999000111');
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
    :'sessionOrphanCascadeID',
    :'eventOrphanWithSessionID',
    'Session Orphan Cascade Test',
    '2025-06-09 10:00:00-04',
    '2025-06-09 10:30:00-04',
    'virtual',
    true,
    'zoom',
    true
);
insert into meeting (meeting_id, session_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingOrphanSessionCascadeID', :'sessionOrphanCascadeID', 'zoom', '222333444', 'https://zoom.us/j/222333444');

-- Event: needs meeting create with password required (published, meeting_requires_password=true)
-- Initially set meeting_in_sync=true to not interfere with other tests
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
    meeting_requested,
    meeting_requires_password,
    published
) values (
    :'eventRequiresPasswordID',
    :'groupID',
    'Event Requires Password Test',
    'event-requires-password-test',
    'Test event with meeting_requires_password=true',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-10 10:00:00-04',
    '2025-06-10 11:00:00-04',
    true,
    'zoom',
    true,
    true,
    true
);

-- Event: unpublished event needing create (should NOT be returned)
-- Initially set meeting_in_sync=true to not interfere with other tests
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
    meeting_requested,
    published
) values (
    :'eventUnpublishedCreateID',
    :'groupID',
    'Event Unpublished Create Test',
    'event-unpublished-create-test',
    'Test unpublished event should not sync',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-11 10:00:00-04',
    '2025-06-11 11:00:00-04',
    true,
    'zoom',
    true,
    false
);

-- Event: unpublished event needing delete (has meeting, should trigger delete)
-- Initially set meeting_in_sync=true to not interfere with other tests
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
    meeting_requested,
    published
) values (
    :'eventUnpublishedDeleteID',
    :'groupID',
    'Event Unpublished Delete Test',
    'event-unpublished-delete-test',
    'Test unpublished event with meeting triggers delete',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-12 10:00:00-04',
    '2025-06-12 11:00:00-04',
    true,
    'zoom',
    true,
    false
);
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingEventUnpublishedDeleteID', :'eventUnpublishedDeleteID', 'zoom', '555666777', 'https://zoom.us/j/555666777');

-- Event: unpublished event with sessions for testing session sync
-- Initially set meeting_in_sync=true to not interfere with other tests
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
    meeting_requested,
    meeting_in_sync,
    published
) values (
    :'eventUnpublishedSessionID',
    :'groupID',
    'Event Unpublished Session Test',
    'event-unpublished-session-test',
    'Test unpublished event with sessions',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-13 10:00:00-04',
    '2025-06-13 11:00:00-04',
    false,
    null,
    false
);

-- Session: on unpublished event, needs create (should NOT be returned)
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
    :'sessionUnpublishedCreateID',
    :'eventUnpublishedSessionID',
    'Session Unpublished Create Test',
    '2025-06-13 10:00:00-04',
    '2025-06-13 10:30:00-04',
    'virtual',
    true,
    'zoom',
    true
);

-- Session: on unpublished event, needs delete (has meeting)
-- NOTE: Meeting inserted later in Test 21 to avoid interfering with earlier delete tests
-- Initially set meeting_in_sync=true to not interfere with other tests
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
    :'sessionUnpublishedDeleteID',
    :'eventUnpublishedSessionID',
    'Session Unpublished Delete Test',
    '2025-06-13 10:30:00-04',
    '2025-06-13 11:00:00-04',
    'virtual',
    true,
    'zoom',
    true
);

-- Event: meeting disabled on active event (should trigger delete)
-- Initially set meeting_in_sync=true to not interfere with other tests
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
    meeting_requested,
    meeting_in_sync,
    published
) values (
    :'eventMeetingDisabledID',
    :'groupID',
    'Event Meeting Disabled Test',
    'event-meeting-disabled-test',
    'Test event with meeting disabled',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-14 10:00:00-04',
    '2025-06-14 11:00:00-04',
    false,
    true,
    true
);
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingEventMeetingDisabledID', :'eventMeetingDisabledID', 'zoom', '321321321', 'https://zoom.us/j/321321321');

-- Session: meeting disabled on active session (parent event is active)
-- Initially set meeting_in_sync=true to not interfere with other tests
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_requested,
    meeting_in_sync
) values (
    :'sessionMeetingDisabledID',
    :'eventInSyncID',
    'Session Meeting Disabled Test',
    '2025-06-05 11:30:00-04',
    '2025-06-05 12:00:00-04',
    'virtual',
    false,
    true
);
insert into meeting (meeting_id, session_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingSessionMeetingDisabledID', :'sessionMeetingDisabledID', 'zoom', '654654654', 'https://zoom.us/j/654654654');

-- Event: canceled before meeting created (no meeting row)
-- Initially set meeting_in_sync=true to not interfere with other tests
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

    canceled,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'eventCanceledNoMeetingID',
    :'groupID',
    'Event Canceled No Meeting Test',
    'event-canceled-no-meeting-test',
    'Test event canceled before meeting created',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-15 10:00:00-04',
    '2025-06-15 11:00:00-04',

    true,
    true,
    'zoom',
    true
);

-- Session: on canceled event, no meeting row
-- Initially set meeting_in_sync=true to not interfere with other tests
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
    :'sessionCanceledNoMeetingID',
    :'eventCanceledNoMeetingID',
    'Session Canceled No Meeting Test',
    '2025-06-15 10:00:00-04',
    '2025-06-15 10:30:00-04',
    'virtual',
    true,
    'zoom',
    true
);

-- Session: with meeting_requires_password=true (on eventInSyncID which is active)
-- Initially set meeting_in_sync=true to not interfere with other tests
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    meeting_requires_password
) values (
    :'sessionRequiresPasswordID',
    :'eventInSyncID',
    'Session Requires Password Test',
    '2025-06-05 12:00:00-04',
    '2025-06-05 12:30:00-04',
    'virtual',
    true,
    'zoom',
    true,
    true
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test 1: Event create - returns event with delete=false, no meeting_id
-- Priority: create/update operations come before deletes
select is(
    (select row_to_json(r)::jsonb - 'starts_at' from get_meeting_out_of_sync() r),
    '{
        "delete": false,
        "duration_secs": 3600,
        "event_id": "00000000-0000-0000-0000-000000000101",
        "hosts": ["host1@example.com", "host2@example.com"],
        "meeting_id": null,
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": null,
        "session_id": null,
        "timezone": "America/New_York",
        "topic": "Event Create Test",
        "join_url": null
    }'::jsonb,
    'Event needing create returns correctly'
);

-- Mark event as synced to test next case
update event set meeting_in_sync = true where event_id = :'eventCreateID';

-- Test 2: Event update - returns event with delete=false, has provider_meeting_id
select is(
    (select row_to_json(r)::jsonb - 'starts_at' from get_meeting_out_of_sync() r),
    '{
        "delete": false,
        "duration_secs": 7200,
        "event_id": "00000000-0000-0000-0000-000000000102",
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000301",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": "pass123",
        "provider_meeting_id": "123456789",
        "session_id": null,
        "timezone": "America/Chicago",
        "topic": "Event Update Test",
        "join_url": "https://zoom.us/j/123456789"
    }'::jsonb,
    'Event needing update returns correctly'
);

-- Mark event as synced to test next case
update event set meeting_in_sync = true where event_id = :'eventUpdateID';

-- Test 3: Session create - returns session with delete=false, no meeting_id
-- Priority: session create/update comes before event delete
select is(
    (select row_to_json(r)::jsonb - 'starts_at' from get_meeting_out_of_sync() r),
    '{
        "delete": false,
        "duration_secs": 1800,
        "event_id": null,
        "hosts": ["sessionhost@example.com"],
        "meeting_id": null,
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": null,
        "session_id": "00000000-0000-0000-0000-000000000201",
        "timezone": "America/New_York",
        "topic": "Session Create Test",
        "join_url": null
    }'::jsonb,
    'Session needing create returns correctly'
);

-- Mark session as synced to test next case
update session set meeting_in_sync = true where session_id = :'sessionCreateID';

-- Test 4: Session update - returns session with delete=false, has provider_meeting_id
select is(
    (select row_to_json(r)::jsonb - 'starts_at' from get_meeting_out_of_sync() r),
    '{
        "delete": false,
        "duration_secs": 1800,
        "event_id": null,
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000304",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": "sesspass",
        "provider_meeting_id": "444555666",
        "session_id": "00000000-0000-0000-0000-000000000202",
        "timezone": "America/New_York",
        "topic": "Session Update Test",
        "join_url": "https://zoom.us/j/444555666"
    }'::jsonb,
    'Session needing update returns correctly'
);

-- Mark session as synced to test next case
update session set meeting_in_sync = true where session_id = :'sessionUpdateID';

-- Test 5: Event delete (canceled) - returns event with delete=true
-- Priority: delete operations come after create/update
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": "00000000-0000-0000-0000-000000000103",
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000302",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": "987654321",
        "session_id": null,
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": "https://zoom.us/j/987654321"
    }'::jsonb,
    'Event needing delete (canceled) returns correctly'
);

-- Mark event as synced to test next case
update event set meeting_in_sync = true where event_id = :'eventDeleteCanceledID';

-- Test 6: Event delete (soft deleted) - returns event with delete=true
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": "00000000-0000-0000-0000-000000000104",
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000303",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": "111222333",
        "session_id": null,
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": "https://zoom.us/j/111222333"
    }'::jsonb,
    'Event needing delete (soft deleted) returns correctly'
);

-- Mark event as synced to test next case
update event set meeting_in_sync = true where event_id = :'eventDeleteSoftID';

-- Test 7: Session delete (parent canceled) - returns session with delete=true
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": null,
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000305",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": "777888999",
        "session_id": "00000000-0000-0000-0000-000000000203",
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": "https://zoom.us/j/777888999"
    }'::jsonb,
    'Session needing delete (parent canceled) returns correctly'
);

-- Remove session meeting and mark session as synced to test next case
delete from meeting where meeting_id = :'meetingSessionDeleteParentCanceledID';
update session set meeting_in_sync = true where session_id = :'sessionDeleteParentCanceledID';

-- Test 8: Session delete (parent deleted) - returns session with delete=true
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": null,
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000306",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": "000111222",
        "session_id": "00000000-0000-0000-0000-000000000204",
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": "https://zoom.us/j/000111222"
    }'::jsonb,
    'Session needing delete (parent deleted) returns correctly'
);

-- Remove session meeting and mark session as synced to test next case
delete from meeting where meeting_id = :'meetingSessionDeleteParentDeletedID';
update session set meeting_in_sync = true where session_id = :'sessionDeleteParentDeletedID';

-- Test 9: Orphan event meeting - hard delete event triggers ON DELETE SET NULL
delete from event where event_id = :'eventOrphanID';
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": null,
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000307",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": "333444555",
        "session_id": null,
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": "https://zoom.us/j/333444555"
    }'::jsonb,
    'Orphan event meeting returns with delete=true'
);
delete from meeting where meeting_id = :'meetingOrphanEventID';

-- Test 10: Orphan session meeting - hard delete session triggers ON DELETE SET NULL
delete from session where session_id = :'sessionOrphanID';
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": null,
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000308",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": "666777888",
        "session_id": null,
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": "https://zoom.us/j/666777888"
    }'::jsonb,
    'Orphan session meeting returns with delete=true'
);
delete from meeting where meeting_id = :'meetingOrphanSessionID';

-- Test 11-12: Multiple orphan meetings - event delete cascades to session delete
-- Both meetings become orphans (event meeting via ON DELETE SET NULL on event,
-- session meeting via cascade delete of session then ON DELETE SET NULL)
delete from event where event_id = :'eventOrphanWithSessionID';
select is(
    (select count(*) from get_meeting_out_of_sync() where delete = true),
    1::bigint,
    'First orphan meeting detected after cascade delete'
);
delete from meeting where meeting_id = (select meeting_id from get_meeting_out_of_sync());
select is(
    (select count(*) from get_meeting_out_of_sync() where delete = true),
    1::bigint,
    'Second orphan meeting detected after cascade delete'
);
delete from meeting where meeting_id = (select meeting_id from get_meeting_out_of_sync());

-- Test 13: Event in sync - should NOT be returned
-- (eventInSyncID has meeting_in_sync=true, so should be skipped)
-- At this point all out-of-sync items have been processed
select is(
    (select count(*) from get_meeting_out_of_sync()),
    0::bigint,
    'Event in sync is not returned'
);

-- Test 14: Verify in-sync events are not returned by re-adding out-of-sync event
update event set meeting_in_sync = false where event_id = :'eventCreateID';
select is(
    (select event_id::text from get_meeting_out_of_sync()),
    '00000000-0000-0000-0000-000000000101',
    'Only out-of-sync events are returned, in-sync are skipped'
);
update event set meeting_in_sync = true where event_id = :'eventCreateID';

-- Test 15: Verify no-meeting-requested events are not returned
select is(
    (select count(*) from get_meeting_out_of_sync()),
    0::bigint,
    'Events with meeting_requested=false are not returned'
);

-- Test 16: Verify empty queue after all items processed
select is(
    (select count(*) from get_meeting_out_of_sync()),
    0::bigint,
    'Empty queue returns empty result'
);

-- Test 17: Event with requires_password=true returns the flag correctly
update event set meeting_in_sync = false where event_id = :'eventRequiresPasswordID';
select is(
    (select row_to_json(r)::jsonb - 'starts_at' from get_meeting_out_of_sync() r),
    '{
        "delete": false,
        "duration_secs": 3600,
        "event_id": "00000000-0000-0000-0000-000000000110",
        "hosts": null,
        "meeting_id": null,
        "meeting_provider_id": "zoom",
        "requires_password": true,
        "password": null,
        "provider_meeting_id": null,
        "session_id": null,
        "timezone": "America/New_York",
        "topic": "Event Requires Password Test",
        "join_url": null
    }'::jsonb,
    'Event with requires_password=true returns flag correctly'
);
update event set meeting_in_sync = true where event_id = :'eventRequiresPasswordID';

-- Test 18: Unpublished event without meeting returns for delete (to mark as synced)
-- This ensures events that were canceled/unpublished before meeting creation don't wedge the queue
update event set meeting_in_sync = false where event_id = :'eventUnpublishedCreateID';
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": "00000000-0000-0000-0000-000000000111",
        "hosts": null,
        "meeting_id": null,
        "meeting_provider_id": null,
        "requires_password": null,
        "password": null,
        "provider_meeting_id": null,
        "session_id": null,
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": null
    }'::jsonb,
    'Unpublished event without meeting returns for delete'
);
update event set meeting_in_sync = true where event_id = :'eventUnpublishedCreateID';

-- Test 19: Unpublished event with meeting triggers delete
update event set meeting_in_sync = false where event_id = :'eventUnpublishedDeleteID';
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": "00000000-0000-0000-0000-000000000112",
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000311",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": "555666777",
        "session_id": null,
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": "https://zoom.us/j/555666777"
    }'::jsonb,
    'Unpublished event with meeting triggers delete'
);
update event set meeting_in_sync = true where event_id = :'eventUnpublishedDeleteID';

-- Test 20: Session on unpublished event without meeting returns for delete (to mark as synced)
update session set meeting_in_sync = false where session_id = :'sessionUnpublishedCreateID';
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": null,
        "hosts": null,
        "meeting_id": null,
        "meeting_provider_id": null,
        "requires_password": null,
        "password": null,
        "provider_meeting_id": null,
        "session_id": "00000000-0000-0000-0000-000000000208",
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": null
    }'::jsonb,
    'Session on unpublished event without meeting returns for delete'
);
update session set meeting_in_sync = true where session_id = :'sessionUnpublishedCreateID';

-- Test 21: Session on unpublished event with meeting triggers delete
-- Insert meeting and set meeting_in_sync=false now to avoid interfering with earlier delete tests
insert into meeting (meeting_id, session_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingSessionUnpublishedDeleteID', :'sessionUnpublishedDeleteID', 'zoom', '888999000', 'https://zoom.us/j/888999000');
update session set meeting_in_sync = false where session_id = :'sessionUnpublishedDeleteID';
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": null,
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000312",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": "888999000",
        "session_id": "00000000-0000-0000-0000-000000000209",
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": "https://zoom.us/j/888999000"
    }'::jsonb,
    'Session on unpublished event with meeting triggers delete'
);
delete from meeting where meeting_id = :'meetingSessionUnpublishedDeleteID';
update session set meeting_in_sync = true where session_id = :'sessionUnpublishedDeleteID';

-- Test 22: Event republished triggers create (was unpublished, now published)
update event set published = true, meeting_in_sync = false where event_id = :'eventUnpublishedCreateID';
select is(
    (select row_to_json(r)::jsonb - 'starts_at' from get_meeting_out_of_sync() r),
    '{
        "delete": false,
        "duration_secs": 3600,
        "event_id": "00000000-0000-0000-0000-000000000111",
        "hosts": null,
        "meeting_id": null,
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": null,
        "session_id": null,
        "timezone": "America/New_York",
        "topic": "Event Unpublished Create Test",
        "join_url": null
    }'::jsonb,
    'Event republished triggers create'
);
update event set meeting_in_sync = true where event_id = :'eventUnpublishedCreateID';

-- Test 23: Verify all unpublished test data cleaned up
select is(
    (select count(*) from get_meeting_out_of_sync()),
    0::bigint,
    'All unpublished test data cleaned up'
);

-- Test 24: Event with meeting disabled triggers delete
update event set meeting_in_sync = false where event_id = :'eventMeetingDisabledID';
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": "00000000-0000-0000-0000-000000000114",
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000313",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": "321321321",
        "session_id": null,
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": "https://zoom.us/j/321321321"
    }'::jsonb,
    'Event with meeting disabled triggers delete'
);
delete from meeting where meeting_id = :'meetingEventMeetingDisabledID';
update event set meeting_in_sync = true where event_id = :'eventMeetingDisabledID';

-- Test 25: Session with meeting disabled triggers delete
update session set meeting_in_sync = false where session_id = :'sessionMeetingDisabledID';
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": null,
        "hosts": null,
        "meeting_id": "00000000-0000-0000-0000-000000000314",
        "meeting_provider_id": "zoom",
        "requires_password": null,
        "password": null,
        "provider_meeting_id": "654654654",
        "session_id": "00000000-0000-0000-0000-000000000210",
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": "https://zoom.us/j/654654654"
    }'::jsonb,
    'Session with meeting disabled triggers delete'
);
delete from meeting where meeting_id = :'meetingSessionMeetingDisabledID';
update session set meeting_in_sync = true where session_id = :'sessionMeetingDisabledID';

-- Test 26: Event canceled before meeting created (no meeting row)
update event set meeting_in_sync = false where event_id = :'eventCanceledNoMeetingID';
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": "00000000-0000-0000-0000-000000000115",
        "hosts": null,
        "meeting_id": null,
        "meeting_provider_id": null,
        "requires_password": null,
        "password": null,
        "provider_meeting_id": null,
        "session_id": null,
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": null
    }'::jsonb,
    'Event canceled before meeting created returns with delete=true and null meeting fields'
);
update event set meeting_in_sync = true where event_id = :'eventCanceledNoMeetingID';

-- Test 27: Session on canceled event before meeting created (no meeting row)
update session set meeting_in_sync = false where session_id = :'sessionCanceledNoMeetingID';
select is(
    (select row_to_json(r)::jsonb from get_meeting_out_of_sync() r),
    '{
        "delete": true,
        "duration_secs": null,
        "event_id": null,
        "hosts": null,
        "meeting_id": null,
        "meeting_provider_id": null,
        "requires_password": null,
        "password": null,
        "provider_meeting_id": null,
        "session_id": "00000000-0000-0000-0000-000000000211",
        "starts_at": null,
        "timezone": null,
        "topic": null,
        "join_url": null
    }'::jsonb,
    'Session on canceled event before meeting created returns with delete=true and null meeting fields'
);
update session set meeting_in_sync = true where session_id = :'sessionCanceledNoMeetingID';

-- Test 28: Session with requires_password=true returns the flag correctly
update session set meeting_in_sync = false where session_id = :'sessionRequiresPasswordID';
select is(
    (select row_to_json(r)::jsonb - 'starts_at' from get_meeting_out_of_sync() r),
    '{
        "delete": false,
        "duration_secs": 1800,
        "event_id": null,
        "hosts": null,
        "meeting_id": null,
        "meeting_provider_id": "zoom",
        "requires_password": true,
        "password": null,
        "provider_meeting_id": null,
        "session_id": "00000000-0000-0000-0000-000000000212",
        "timezone": "America/New_York",
        "topic": "Session Requires Password Test",
        "join_url": null
    }'::jsonb,
    'Session with requires_password=true returns flag correctly'
);
update session set meeting_in_sync = true where session_id = :'sessionRequiresPasswordID';

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
