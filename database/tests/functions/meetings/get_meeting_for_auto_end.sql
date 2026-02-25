-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCanceledID '00000000-0000-0000-0000-000000000105'
\set eventNotOverdueID '00000000-0000-0000-0000-000000000103'
\set eventOlderOverdueID '00000000-0000-0000-0000-000000000102'
\set eventProcessedID '00000000-0000-0000-0000-000000000104'
\set eventRecentOverdueID '00000000-0000-0000-0000-000000000101'
\set eventWithSessionsID '00000000-0000-0000-0000-000000000106'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000002'
\set sessionOutOfSyncID '00000000-0000-0000-0000-000000000202'
\set sessionOverdueID '00000000-0000-0000-0000-000000000201'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'categoryID', 'Conference', 'conference', :'communityID');

-- Group category
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

-- Event candidates and exclusions
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
    meeting_requested,
    published
) values
(
    :'eventRecentOverdueID',
    :'groupID',
    'Event Recent Overdue',
    'event-recent-overdue',
    'Recent overdue event meeting',
    'America/New_York',
    :'categoryID',
    'virtual',
    current_timestamp - interval '1 hour',
    current_timestamp - interval '25 minutes',
    100,

    true,
    'zoom',
    true,
    true
),
(
    :'eventOlderOverdueID',
    :'groupID',
    'Event Older Overdue',
    'event-older-overdue',
    'Older overdue event meeting',
    'America/New_York',
    :'categoryID',
    'virtual',
    current_timestamp - interval '3 hours',
    current_timestamp - interval '90 minutes',
    100,

    true,
    'zoom',
    true,
    true
),
(
    :'eventNotOverdueID',
    :'groupID',
    'Event Not Overdue',
    'event-not-overdue',
    'Event still inside grace window',
    'America/New_York',
    :'categoryID',
    'virtual',
    current_timestamp - interval '40 minutes',
    current_timestamp - interval '5 minutes',
    100,

    true,
    'zoom',
    true,
    true
),
(
    :'eventProcessedID',
    :'groupID',
    'Event Already Checked',
    'event-already-checked',
    'Event meeting already checked',
    'America/New_York',
    :'categoryID',
    'virtual',
    current_timestamp - interval '2 hours',
    current_timestamp - interval '40 minutes',
    100,

    true,
    'zoom',
    true,
    true
),
(
    :'eventCanceledID',
    :'groupID',
    'Event Canceled',
    'event-canceled',
    'Canceled event meeting',
    'America/New_York',
    :'categoryID',
    'virtual',
    current_timestamp - interval '2 hours',
    current_timestamp - interval '40 minutes',
    100,

    true,
    'zoom',
    true,
    true
),
(
    :'eventWithSessionsID',
    :'groupID',
    'Event With Sessions',
    'event-with-sessions',
    'Parent event for session meetings',
    'America/New_York',
    :'categoryID',
    'virtual',
    current_timestamp - interval '2 hours',
    current_timestamp + interval '2 hours',
    100,

    true,
    'zoom',
    true,
    true
);

update event
set canceled = true,
    published = false
where event_id = :'eventCanceledID'::uuid;

-- Session candidates and exclusions
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
) values
(
    :'sessionOverdueID',
    :'eventWithSessionsID',
    'Session Overdue',
    current_timestamp - interval '45 minutes',
    current_timestamp - interval '15 minutes',
    'virtual',

    true,
    'zoom',
    true
),
(
    :'sessionOutOfSyncID',
    :'eventWithSessionsID',
    'Session Out Of Sync',
    current_timestamp - interval '50 minutes',
    current_timestamp - interval '20 minutes',
    'virtual',

    false,
    'zoom',
    true
);

-- Meeting rows
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    event_id
) values
(
    '00000000-0000-0000-0000-000000000301',
    'https://zoom.us/j/event-recent-overdue',
    'zoom',
    'event-recent-overdue',

    :'eventRecentOverdueID'
),
(
    '00000000-0000-0000-0000-000000000302',
    'https://zoom.us/j/event-older-overdue',
    'zoom',
    'event-older-overdue',

    :'eventOlderOverdueID'
),
(
    '00000000-0000-0000-0000-000000000303',
    'https://zoom.us/j/event-not-overdue',
    'zoom',
    'event-not-overdue',

    :'eventNotOverdueID'
),
(
    '00000000-0000-0000-0000-000000000304',
    'https://zoom.us/j/event-processed',
    'zoom',
    'event-processed',

    :'eventProcessedID'
),
(
    '00000000-0000-0000-0000-000000000305',
    'https://zoom.us/j/event-canceled',
    'zoom',
    'event-canceled',

    :'eventCanceledID'
);

insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    session_id
) values
(
    '00000000-0000-0000-0000-000000000306',
    'https://zoom.us/j/session-overdue',
    'zoom',
    'session-overdue',

    :'sessionOverdueID'
),
(
    '00000000-0000-0000-0000-000000000307',
    'https://zoom.us/j/session-out-of-sync',
    'zoom',
    'session-out-of-sync',

    :'sessionOutOfSyncID'
);

update meeting
set auto_end_check_at = current_timestamp - interval '1 minute',
    auto_end_check_outcome = 'auto_ended'
where provider_meeting_id = 'event-processed';

-- ============================================================================
-- TESTS
-- ============================================================================

-- Returns most recently overdue eligible event meeting first
select is(
    (select provider_meeting_id from get_meeting_for_auto_end()),
    'event-recent-overdue',
    'Returns the most recently overdue eligible event meeting first'
);
select is(
    (select meeting_provider_id from get_meeting_for_auto_end()),
    'zoom',
    'Returns the provider ID for the selected overdue meeting'
);

-- Mark first event result as checked and fetch next event result
update meeting
set auto_end_check_at = current_timestamp,
    auto_end_check_outcome = 'already_not_running'
where provider_meeting_id = 'event-recent-overdue';
select is(
    (select provider_meeting_id from get_meeting_for_auto_end()),
    'event-older-overdue',
    'Returns the next overdue event meeting after the first is checked'
);

-- Mark second event result as checked and fall back to overdue sessions
update meeting
set auto_end_check_at = current_timestamp,
    auto_end_check_outcome = 'already_not_running'
where provider_meeting_id = 'event-older-overdue';
select is(
    (select provider_meeting_id from get_meeting_for_auto_end()),
    'session-overdue',
    'Falls back to overdue session meetings after events are checked'
);

-- Mark final overdue result and expect no additional candidates
update meeting
set auto_end_check_at = current_timestamp,
    auto_end_check_outcome = 'already_not_running'
where provider_meeting_id = 'session-overdue';
select is(
    (select count(*) from get_meeting_for_auto_end()),
    0::bigint,
    'Returns no rows once all eligible overdue meetings are checked'
);

-- Non-overdue meetings stay unchecked and excluded
select is(
    (select auto_end_check_at is null from meeting where provider_meeting_id = 'event-not-overdue'),
    true,
    'Keeps non-overdue meetings unchecked and excluded'
);

-- Pre-checked meetings remain checked and excluded
select is(
    (select auto_end_check_at is not null from meeting where provider_meeting_id = 'event-processed'),
    true,
    'Keeps already checked meetings excluded from candidate selection'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
