-- Seeds schema-95 meeting sync states for the lost meeting deletions repair test.

begin;

\set communityID '96000000-0000-0000-0000-000000000001'
\set eventCategoryID '96000000-0000-0000-0000-000000000002'
\set failedDeletionEventID '96000000-0000-0000-0000-000000000003'
\set failedDeletionMeetingID '96000000-0000-0000-0000-000000000004'
\set failedDeletionTicketTypeID '96000000-0000-0000-0000-000000000005'
\set groupCategoryID '96000000-0000-0000-0000-000000000006'
\set groupID '96000000-0000-0000-0000-000000000007'
\set manualUrlEventID '96000000-0000-0000-0000-000000000008'
\set manualUrlEventMeetingID '96000000-0000-0000-0000-000000000009'
\set manualUrlEventTicketTypeID '96000000-0000-0000-0000-000000000010'
\set manualUrlSessionID '96000000-0000-0000-0000-000000000011'
\set manualUrlSessionMeetingID '96000000-0000-0000-0000-000000000012'
\set noMeetingEventID '96000000-0000-0000-0000-000000000013'
\set noMeetingTicketTypeID '96000000-0000-0000-0000-000000000014'
\set nullRequestedEventID '96000000-0000-0000-0000-000000000029'
\set nullRequestedEventMeetingID '96000000-0000-0000-0000-000000000030'
\set nullRequestedEventTicketTypeID '96000000-0000-0000-0000-000000000031'
\set nullRequestedManualUrlEventID '96000000-0000-0000-0000-000000000049'
\set nullRequestedManualUrlEventMeetingID '96000000-0000-0000-0000-000000000050'
\set nullRequestedManualUrlEventTicketTypeID '96000000-0000-0000-0000-000000000051'
\set nullRequestedManualUrlSessionID '96000000-0000-0000-0000-000000000052'
\set nullRequestedManualUrlSessionMeetingID '96000000-0000-0000-0000-000000000053'
\set nullRequestedOtherUrlEventID '96000000-0000-0000-0000-000000000059'
\set nullRequestedOtherUrlEventMeetingID '96000000-0000-0000-0000-000000000060'
\set nullRequestedOtherUrlEventTicketTypeID '96000000-0000-0000-0000-000000000061'
\set nullRequestedOtherUrlSessionID '96000000-0000-0000-0000-000000000062'
\set nullRequestedOtherUrlSessionMeetingID '96000000-0000-0000-0000-000000000063'
\set nullRequestedPendingEventID '96000000-0000-0000-0000-000000000054'
\set nullRequestedPendingEventMeetingID '96000000-0000-0000-0000-000000000055'
\set nullRequestedPendingEventTicketTypeID '96000000-0000-0000-0000-000000000056'
\set nullRequestedPendingSessionID '96000000-0000-0000-0000-000000000057'
\set nullRequestedPendingSessionMeetingID '96000000-0000-0000-0000-000000000058'
\set nullRequestedRecordedEventID '96000000-0000-0000-0000-000000000044'
\set nullRequestedRecordedEventMeetingID '96000000-0000-0000-0000-000000000045'
\set nullRequestedRecordedEventTicketTypeID '96000000-0000-0000-0000-000000000046'
\set nullRequestedRecordedSessionID '96000000-0000-0000-0000-000000000047'
\set nullRequestedRecordedSessionMeetingID '96000000-0000-0000-0000-000000000048'
\set nullRequestedSessionID '96000000-0000-0000-0000-000000000032'
\set nullRequestedSessionMeetingID '96000000-0000-0000-0000-000000000033'
\set otherUrlEventID '96000000-0000-0000-0000-000000000039'
\set otherUrlEventMeetingID '96000000-0000-0000-0000-000000000040'
\set otherUrlEventTicketTypeID '96000000-0000-0000-0000-000000000041'
\set otherUrlSessionID '96000000-0000-0000-0000-000000000042'
\set otherUrlSessionMeetingID '96000000-0000-0000-0000-000000000043'
\set outOfBoundsSessionID '96000000-0000-0000-0000-000000000022'
\set outOfBoundsSessionMeetingID '96000000-0000-0000-0000-000000000023'
\set recordedEventID '96000000-0000-0000-0000-000000000024'
\set recordedEventMeetingID '96000000-0000-0000-0000-000000000025'
\set recordedEventTicketTypeID '96000000-0000-0000-0000-000000000026'
\set recordedSessionID '96000000-0000-0000-0000-000000000027'
\set recordedSessionMeetingID '96000000-0000-0000-0000-000000000028'
\set requestedEventID '96000000-0000-0000-0000-000000000034'
\set requestedEventMeetingID '96000000-0000-0000-0000-000000000035'
\set requestedEventTicketTypeID '96000000-0000-0000-0000-000000000036'
\set requestedSessionID '96000000-0000-0000-0000-000000000037'
\set requestedSessionMeetingID '96000000-0000-0000-0000-000000000038'
\set requeuedEventID '96000000-0000-0000-0000-000000000015'
\set requeuedEventMeetingID '96000000-0000-0000-0000-000000000016'
\set requeuedEventTicketTypeID '96000000-0000-0000-0000-000000000017'
\set requeuedSessionID '96000000-0000-0000-0000-000000000018'
\set requeuedSessionMeetingID '96000000-0000-0000-0000-000000000019'
\set sessionsEventID '96000000-0000-0000-0000-000000000020'
\set sessionsTicketTypeID '96000000-0000-0000-0000-000000000021'

-- Community hosting the migration fixtures
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
    'Lost meeting deletions upgrade fixtures',
    'Meeting Deletions Community',
    'https://example.test/logo.png',
    'meeting-deletions-community'
);

-- Event category of the fixture events
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Meeting deletions events');

-- Group category of the fixture group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Meeting deletions groups');

-- Group owning the fixture events
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Meeting Deletions Group', 'meeting-deletions-group');

-- Event whose failed meeting deletion is still awaiting a retry
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Failed Deletion Event description',
    '2099-01-01 12:00:00+00',
    :'eventCategoryID',
    :'failedDeletionEventID',
    'virtual',
    :'groupID',
    'Failed Deletion Event',
    'failed-deletion-event',
    '2099-01-01 09:00:00+00',
    'UTC',
    'meeting deletion failed',
    true,
    null,
    'zoom',
    false
);

-- Event that reuses its leaked meeting URL as the manual link
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Manual URL Event description',
    '2099-01-02 12:00:00+00',
    :'eventCategoryID',
    :'manualUrlEventID',
    'virtual',
    :'groupID',
    'Manual URL Event',
    'manual-url-event',
    '2099-01-02 09:00:00+00',
    'UTC',
    null,
    null,
    'https://zoom.example/j/manual-url-event',
    'zoom',
    false
);

-- Event without meeting work or a linked meeting
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'No Meeting Event description',
    '2099-01-03 12:00:00+00',
    :'eventCategoryID',
    :'noMeetingEventID',
    'virtual',
    :'groupID',
    'No Meeting Event',
    'no-meeting-event',
    '2099-01-03 09:00:00+00',
    'UTC',
    null,
    null,
    null,
    'zoom',
    false
);

-- Legacy event with an unset meeting request and a linked meeting
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Null Requested Event description',
    '2099-01-07 12:00:00+00',
    :'eventCategoryID',
    :'nullRequestedEventID',
    'virtual',
    :'groupID',
    'Null Requested Event',
    'null-requested-event',
    '2099-01-07 09:00:00+00',
    'UTC',
    null,
    null,
    null,
    'zoom',
    null
);

-- Event with an unset meeting request reusing its pending deletion meeting URL
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Null Requested Manual URL Event description',
    '2099-01-11 12:00:00+00',
    :'eventCategoryID',
    :'nullRequestedManualUrlEventID',
    'virtual',
    :'groupID',
    'Null Requested Manual URL Event',
    'null-requested-manual-url-event',
    '2099-01-11 09:00:00+00',
    'UTC',
    null,
    false,
    'https://zoom.example/j/null-requested-manual-url-event',
    'zoom',
    null
);

-- Event with an unset meeting request whose pending deletion left an unrelated manual link
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Null Requested Other URL Event description',
    '2099-01-13 12:00:00+00',
    :'eventCategoryID',
    :'nullRequestedOtherUrlEventID',
    'virtual',
    :'groupID',
    'Null Requested Other URL Event',
    'null-requested-other-url-event',
    '2099-01-13 09:00:00+00',
    'UTC',
    null,
    false,
    'https://meet.example/j/null-requested-other-url-event',
    'zoom',
    null
);

-- Event with an unset meeting request whose meeting deletion is pending
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Null Requested Pending Event description',
    '2099-01-12 12:00:00+00',
    :'eventCategoryID',
    :'nullRequestedPendingEventID',
    'virtual',
    :'groupID',
    'Null Requested Pending Event',
    'null-requested-pending-event',
    '2099-01-12 09:00:00+00',
    'UTC',
    null,
    false,
    null,
    'zoom',
    null
);

-- Event with an unset meeting request whose pending deletion meeting has recordings
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Null Requested Recorded Event description',
    '2099-01-10 12:00:00+00',
    :'eventCategoryID',
    :'nullRequestedRecordedEventID',
    'virtual',
    :'groupID',
    'Null Requested Recorded Event',
    'null-requested-recorded-event',
    '2099-01-10 09:00:00+00',
    'UTC',
    null,
    false,
    null,
    'zoom',
    null
);

-- Event whose lost meeting deletion left an unrelated manual link
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Other URL Event description',
    '2099-01-09 12:00:00+00',
    :'eventCategoryID',
    :'otherUrlEventID',
    'virtual',
    :'groupID',
    'Other URL Event',
    'other-url-event',
    '2099-01-09 09:00:00+00',
    'UTC',
    null,
    null,
    'https://meet.example/j/other-url-event',
    'zoom',
    false
);

-- Event whose lost meeting deletion kept captured recordings
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Recorded Event description',
    '2099-01-06 12:00:00+00',
    :'eventCategoryID',
    :'recordedEventID',
    'virtual',
    :'groupID',
    'Recorded Event',
    'recorded-event',
    '2099-01-06 09:00:00+00',
    'UTC',
    null,
    null,
    null,
    'zoom',
    false
);

-- Event whose requested meeting is still awaiting its first sync
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Requested Event description',
    '2099-01-08 12:00:00+00',
    :'eventCategoryID',
    :'requestedEventID',
    'virtual',
    :'groupID',
    'Requested Event',
    'requested-event',
    '2099-01-08 09:00:00+00',
    'UTC',
    null,
    null,
    null,
    'zoom',
    true
);

-- Event whose meeting deletion was lost by a repeated save
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Requeued Event description',
    '2099-01-04 12:00:00+00',
    :'eventCategoryID',
    :'requeuedEventID',
    'virtual',
    :'groupID',
    'Requeued Event',
    'requeued-event',
    '2099-01-04 09:00:00+00',
    'UTC',
    null,
    null,
    null,
    'zoom',
    false
);

-- Event hosting the fixture sessions
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,
    meeting_error,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    20,
    'Sessions Event description',
    '2099-01-05 12:00:00+00',
    :'eventCategoryID',
    :'sessionsEventID',
    'virtual',
    :'groupID',
    'Sessions Event',
    'sessions-event',
    '2099-01-05 09:00:00+00',
    'UTC',
    null,
    null,
    null,
    'zoom',
    null
);

-- Ticket tier required by the failed deletion event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'failedDeletionEventID', :'failedDeletionTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the manual URL event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'manualUrlEventID', :'manualUrlEventTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the event without a meeting
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'noMeetingEventID', :'noMeetingTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the event with an unset meeting request
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'nullRequestedEventID', :'nullRequestedEventTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the null requested manual URL event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'nullRequestedManualUrlEventID', :'nullRequestedManualUrlEventTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the null requested other URL event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'nullRequestedOtherUrlEventID', :'nullRequestedOtherUrlEventTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the null requested pending event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'nullRequestedPendingEventID', :'nullRequestedPendingEventTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the null requested recorded event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'nullRequestedRecordedEventID', :'nullRequestedRecordedEventTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the other URL event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'otherUrlEventID', :'otherUrlEventTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the recorded event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'recordedEventID', :'recordedEventTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the requested event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'requestedEventID', :'requestedEventTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the requeued event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'requeuedEventID', :'requeuedEventTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the sessions event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'sessionsEventID', :'sessionsTicketTypeID', 1, 20, 'General admission');

-- Session that reuses its leaked meeting URL as the manual link
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Manual URL Session',
    :'manualUrlSessionID',
    'virtual',
    '2099-01-05 10:00:00+00',
    '2099-01-05 10:30:00+00',
    null,
    'https://zoom.example/j/manual-url-session',
    'zoom',
    false
);

-- Session with an unset meeting request reusing its pending deletion meeting URL
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Null Requested Manual URL Session',
    :'nullRequestedManualUrlSessionID',
    'virtual',
    '2099-01-05 09:00:00+00',
    '2099-01-05 09:30:00+00',
    false,
    'https://zoom.example/j/null-requested-manual-url-session',
    'zoom',
    null
);

-- Session with an unset meeting request whose pending deletion left an unrelated manual link
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Null Requested Other URL Session',
    :'nullRequestedOtherUrlSessionID',
    'virtual',
    '2099-01-05 11:30:00+00',
    '2099-01-05 12:00:00+00',
    false,
    'https://meet.example/j/null-requested-other-url-session',
    'zoom',
    null
);

-- Session with an unset meeting request whose meeting deletion is pending
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Null Requested Pending Session',
    :'nullRequestedPendingSessionID',
    'virtual',
    '2099-01-05 09:30:00+00',
    '2099-01-05 10:00:00+00',
    false,
    null,
    'zoom',
    null
);

-- Session with an unset meeting request whose pending deletion meeting has recordings
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Null Requested Recorded Session',
    :'nullRequestedRecordedSessionID',
    'virtual',
    '2099-01-05 10:00:00+00',
    '2099-01-05 10:30:00+00',
    false,
    null,
    'zoom',
    null
);

-- Legacy session with an unset meeting request and a linked meeting
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Null Requested Session',
    :'nullRequestedSessionID',
    'virtual',
    '2099-01-05 09:30:00+00',
    '2099-01-05 10:00:00+00',
    null,
    null,
    'zoom',
    null
);

-- Session whose lost meeting deletion left an unrelated manual link
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Other URL Session',
    :'otherUrlSessionID',
    'virtual',
    '2099-01-05 11:30:00+00',
    '2099-01-05 12:00:00+00',
    null,
    'https://meet.example/j/other-url-session',
    'zoom',
    false
);

-- Session whose lost meeting deletion kept captured recordings
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Recorded Session',
    :'recordedSessionID',
    'virtual',
    '2099-01-05 09:00:00+00',
    '2099-01-05 09:30:00+00',
    null,
    null,
    'zoom',
    false
);

-- Session whose requested meeting is still awaiting its first sync
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Requested Session',
    :'requestedSessionID',
    'virtual',
    '2099-01-05 10:30:00+00',
    '2099-01-05 11:00:00+00',
    null,
    null,
    'zoom',
    true
);

-- Session whose meeting deletion was lost by a repeated save
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Requeued Session',
    :'requeuedSessionID',
    'virtual',
    '2099-01-05 11:00:00+00',
    '2099-01-05 11:30:00+00',
    null,
    null,
    'zoom',
    false
);

-- Live session bounds trigger body, which honors the legacy import bypass
\ir ../../migrations/functions/triggers/check_session_within_event_bounds.sql

-- Legacy session outside its event bounds whose meeting deletion was lost
select set_config('ocg.skip_session_bounds_check', 'on', true);
insert into session (
    event_id,
    name,
    session_id,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionsEventID',
    'Out Of Bounds Session',
    :'outOfBoundsSessionID',
    'virtual',
    '2099-01-05 13:00:00+00',
    '2099-01-05 13:30:00+00',
    null,
    null,
    'zoom',
    false
);
select set_config('ocg.skip_session_bounds_check', 'off', true);

-- Provider meeting kept after the failed deletion
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'failedDeletionEventID', 'https://zoom.example/j/failed-deletion-event', :'failedDeletionMeetingID', 'zoom', 'failed-deletion-event');

-- Leaked meeting whose URL the manual URL event reuses
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'manualUrlEventID', 'https://zoom.example/j/manual-url-event', :'manualUrlEventMeetingID', 'zoom', 'manual-url-event');

-- Leaked meeting whose URL the manual URL session reuses
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'manualUrlSessionID', 'https://zoom.example/j/manual-url-session', :'manualUrlSessionMeetingID', 'zoom', 'manual-url-session');

-- Linked meeting of the event with an unset meeting request
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'nullRequestedEventID', 'https://zoom.example/j/null-requested-event', :'nullRequestedEventMeetingID', 'zoom', 'null-requested-event');

-- Pending deletion meeting whose URL the null requested manual URL event reuses
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'nullRequestedManualUrlEventID', 'https://zoom.example/j/null-requested-manual-url-event', :'nullRequestedManualUrlEventMeetingID', 'zoom', 'null-requested-manual-url-event');

-- Pending deletion meeting whose URL the null requested manual URL session reuses
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'nullRequestedManualUrlSessionID', 'https://zoom.example/j/null-requested-manual-url-session', :'nullRequestedManualUrlSessionMeetingID', 'zoom', 'null-requested-manual-url-session');

-- Pending deletion meeting of the null requested other URL event
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'nullRequestedOtherUrlEventID', 'https://zoom.example/j/null-requested-other-url-event', :'nullRequestedOtherUrlEventMeetingID', 'zoom', 'null-requested-other-url-event');

-- Pending deletion meeting of the null requested other URL session
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'nullRequestedOtherUrlSessionID', 'https://zoom.example/j/null-requested-other-url-session', :'nullRequestedOtherUrlSessionMeetingID', 'zoom', 'null-requested-other-url-session');

-- Pending deletion meeting of the null requested pending event
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'nullRequestedPendingEventID', 'https://zoom.example/j/null-requested-pending-event', :'nullRequestedPendingEventMeetingID', 'zoom', 'null-requested-pending-event');

-- Pending deletion meeting of the null requested pending session
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'nullRequestedPendingSessionID', 'https://zoom.example/j/null-requested-pending-session', :'nullRequestedPendingSessionMeetingID', 'zoom', 'null-requested-pending-session');

-- Pending deletion meeting of the null requested recorded event with captured recordings
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id, recording_urls)
values (:'nullRequestedRecordedEventID', 'https://zoom.example/j/null-requested-recorded-event', :'nullRequestedRecordedEventMeetingID', 'zoom', 'null-requested-recorded-event', array['https://zoom.example/rec/null-requested-recorded-event']);

-- Pending deletion meeting of the null requested recorded session with captured recordings
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id, recording_urls)
values (:'nullRequestedRecordedSessionID', 'https://zoom.example/j/null-requested-recorded-session', :'nullRequestedRecordedSessionMeetingID', 'zoom', 'null-requested-recorded-session', array['https://zoom.example/rec/null-requested-recorded-session']);

-- Linked meeting of the session with an unset meeting request
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'nullRequestedSessionID', 'https://zoom.example/j/null-requested-session', :'nullRequestedSessionMeetingID', 'zoom', 'null-requested-session');

-- Leaked meeting of the other URL event
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'otherUrlEventID', 'https://zoom.example/j/other-url-event', :'otherUrlEventMeetingID', 'zoom', 'other-url-event');

-- Leaked meeting of the other URL session
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'otherUrlSessionID', 'https://zoom.example/j/other-url-session', :'otherUrlSessionMeetingID', 'zoom', 'other-url-session');

-- Leaked meeting of the out of bounds session
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'outOfBoundsSessionID', 'https://zoom.example/j/out-of-bounds-session', :'outOfBoundsSessionMeetingID', 'zoom', 'out-of-bounds-session');

-- Leaked meeting of the recorded event with captured recordings
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id, recording_urls)
values (:'recordedEventID', 'https://zoom.example/j/recorded-event', :'recordedEventMeetingID', 'zoom', 'recorded-event', array['https://zoom.example/rec/recorded-event']);

-- Leaked meeting of the recorded session with captured recordings
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id, recording_urls)
values (:'recordedSessionID', 'https://zoom.example/j/recorded-session', :'recordedSessionMeetingID', 'zoom', 'recorded-session', array['https://zoom.example/rec/recorded-session']);

-- Provider meeting of the requested event
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'requestedEventID', 'https://zoom.example/j/requested-event', :'requestedEventMeetingID', 'zoom', 'requested-event');

-- Provider meeting of the requested session
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'requestedSessionID', 'https://zoom.example/j/requested-session', :'requestedSessionMeetingID', 'zoom', 'requested-session');

-- Leaked meeting of the requeued event
insert into meeting (event_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'requeuedEventID', 'https://zoom.example/j/requeued-event', :'requeuedEventMeetingID', 'zoom', 'requeued-event');

-- Leaked meeting of the requeued session
insert into meeting (session_id, join_url, meeting_id, meeting_provider_id, provider_meeting_id)
values (:'requeuedSessionID', 'https://zoom.example/j/requeued-session', :'requeuedSessionMeetingID', 'zoom', 'requeued-session');

commit;
