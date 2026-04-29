-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000001411'
\set communityID '00000000-0000-0000-0000-000000001401'
\set eventCanceledID '00000000-0000-0000-0000-000000001415'
\set eventNotOverdueID '00000000-0000-0000-0000-000000001413'
\set eventOlderOverdueID '00000000-0000-0000-0000-000000001412'
\set eventProcessedID '00000000-0000-0000-0000-000000001414'
\set eventRecentOverdueID '00000000-0000-0000-0000-000000001411'
\set eventWithSessionsID '00000000-0000-0000-0000-000000001416'
\set groupCategoryID '00000000-0000-0000-0000-000000001410'
\set groupID '00000000-0000-0000-0000-000000001402'
\set sessionOutOfSyncID '00000000-0000-0000-0000-000000001422'
\set sessionOverdueID '00000000-0000-0000-0000-000000001421'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'categoryID', 'Conference', :'communityID');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, description)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group', 'A test group');

-- Event candidates and exclusions
insert into event (
    capacity,
    canceled,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    published,
    slug,
    starts_at,
    timezone
) values
(
    100,
    false,
    'Recent overdue event meeting',
    current_timestamp - interval '25 minutes',
    :'categoryID',
    :'eventRecentOverdueID',
    'virtual',
    :'groupID',
    true,
    'zoom',
    true,
    'Event Recent Overdue',
    true,
    'event-recent-overdue',
    current_timestamp - interval '1 hour',
    'UTC'
),
(
    100,
    false,
    'Older overdue event meeting',
    current_timestamp - interval '90 minutes',
    :'categoryID',
    :'eventOlderOverdueID',
    'virtual',
    :'groupID',
    true,
    'zoom',
    true,
    'Event Older Overdue',
    true,
    'event-older-overdue',
    current_timestamp - interval '3 hours',
    'UTC'
),
(
    100,
    false,
    'Event still inside grace window',
    current_timestamp - interval '5 minutes',
    :'categoryID',
    :'eventNotOverdueID',
    'virtual',
    :'groupID',
    true,
    'zoom',
    true,
    'Event Not Overdue',
    true,
    'event-not-overdue',
    current_timestamp - interval '40 minutes',
    'UTC'
),
(
    100,
    false,
    'Event meeting already checked',
    current_timestamp - interval '40 minutes',
    :'categoryID',
    :'eventProcessedID',
    'virtual',
    :'groupID',
    true,
    'zoom',
    true,
    'Event Already Checked',
    true,
    'event-already-checked',
    current_timestamp - interval '2 hours',
    'UTC'
),
(
    100,
    true,
    'Canceled event meeting',
    current_timestamp - interval '40 minutes',
    :'categoryID',
    :'eventCanceledID',
    'virtual',
    :'groupID',
    true,
    'zoom',
    true,
    'Event Canceled',
    false,
    'event-canceled',
    current_timestamp - interval '2 hours',
    'UTC'
),
(
    100,
    false,
    'Parent event for session meetings',
    current_timestamp + interval '2 hours',
    :'categoryID',
    :'eventWithSessionsID',
    'virtual',
    :'groupID',
    true,
    'zoom',
    true,
    'Event With Sessions',
    true,
    'event-with-sessions',
    current_timestamp - interval '2 hours',
    'UTC'
);

-- Session candidates and exclusions
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values
(
    current_timestamp - interval '15 minutes',
    :'eventWithSessionsID',
    true,
    'zoom',
    true,
    'Session Overdue',
    :'sessionOverdueID',
    'virtual',
    current_timestamp - interval '45 minutes'
),
(
    current_timestamp - interval '20 minutes',
    :'eventWithSessionsID',
    false,
    'zoom',
    true,
    'Session Out Of Sync',
    :'sessionOutOfSyncID',
    'virtual',
    current_timestamp - interval '50 minutes'
);

-- Meeting rows
insert into meeting (
    auto_end_check_at,
    auto_end_check_outcome,
    event_id,
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id
) values
(
    null,
    null,
    :'eventRecentOverdueID',
    'https://zoom.us/j/event-recent-overdue',
    '00000000-0000-0000-0000-000000001431',
    'zoom',
    'event-recent-overdue'
),
(
    null,
    null,
    :'eventOlderOverdueID',
    'https://zoom.us/j/event-older-overdue',
    '00000000-0000-0000-0000-000000001432',
    'zoom',
    'event-older-overdue'
),
(
    null,
    null,
    :'eventNotOverdueID',
    'https://zoom.us/j/event-not-overdue',
    '00000000-0000-0000-0000-000000001433',
    'zoom',
    'event-not-overdue'
),
(
    current_timestamp - interval '1 minute',
    'auto_ended',
    :'eventProcessedID',
    'https://zoom.us/j/event-processed',
    '00000000-0000-0000-0000-000000001434',
    'zoom',
    'event-processed'
),
(
    null,
    null,
    :'eventCanceledID',
    'https://zoom.us/j/event-canceled',
    '00000000-0000-0000-0000-000000001435',
    'zoom',
    'event-canceled'
);

-- Session meeting rows
insert into meeting (
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id,
    session_id
) values
(
    'https://zoom.us/j/session-overdue',
    '00000000-0000-0000-0000-000000001436',
    'zoom',
    'session-overdue',
    :'sessionOverdueID'
),
(
    'https://zoom.us/j/session-out-of-sync',
    '00000000-0000-0000-0000-000000001437',
    'zoom',
    'session-out-of-sync',
    :'sessionOutOfSyncID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Returns and claims most recently overdue eligible event meeting first
select is(
    claim_meeting_for_auto_end() - 'meeting_id',
    '{
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "event-recent-overdue"
    }'::jsonb,
    'Returns provider and meeting IDs for the most recently overdue event meeting'
);
select isnt(
    (select auto_end_check_claimed_at from meeting where provider_meeting_id = 'event-recent-overdue'),
    null,
    'Claims the selected overdue event meeting'
);
select is(
    (select auto_end_check_at from meeting where provider_meeting_id = 'event-recent-overdue'),
    null,
    'Does not finalize the auto-end check while claiming'
);

-- Mark first event result as checked and fetch next event result
update meeting
set auto_end_check_at = current_timestamp,
    auto_end_check_claimed_at = null,
    auto_end_check_outcome = 'already_not_running'
where provider_meeting_id = 'event-recent-overdue';
select is(
    claim_meeting_for_auto_end()->>'provider_meeting_id',
    'event-older-overdue',
    'Returns the next overdue event meeting after the first is checked'
);

-- Mark second event result as checked and fall back to overdue sessions
update meeting
set auto_end_check_at = current_timestamp,
    auto_end_check_claimed_at = null,
    auto_end_check_outcome = 'already_not_running'
where provider_meeting_id = 'event-older-overdue';
select is(
    claim_meeting_for_auto_end()->>'provider_meeting_id',
    'session-overdue',
    'Falls back to overdue session meetings after events are checked'
);
select isnt(
    (select auto_end_check_claimed_at from meeting where provider_meeting_id = 'session-overdue'),
    null,
    'Claims the selected overdue session meeting'
);

-- Mark final overdue result and expect no additional candidates
update meeting
set auto_end_check_at = current_timestamp,
    auto_end_check_claimed_at = null,
    auto_end_check_outcome = 'already_not_running'
where provider_meeting_id = 'session-overdue';
select is(
    claim_meeting_for_auto_end(),
    null::jsonb,
    'Returns null once all eligible overdue meetings are checked'
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

-- Out-of-sync session meetings stay unclaimed and excluded
select is(
    (select auto_end_check_claimed_at from meeting where provider_meeting_id = 'session-out-of-sync'),
    null,
    'Keeps out-of-sync session meetings unclaimed and excluded'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
