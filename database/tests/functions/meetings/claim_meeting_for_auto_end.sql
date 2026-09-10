-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a040000-0000-0000-0000-000000000001'
\set eventCanceledID '7a040000-0000-0000-0000-000000000002'
\set eventCategoryID '7a040000-0000-0000-0000-000000000003'
\set eventNotOverdueID '7a040000-0000-0000-0000-000000000004'
\set eventOlderOverdueID '7a040000-0000-0000-0000-000000000005'
\set eventProcessedID '7a040000-0000-0000-0000-000000000006'
\set eventRecentOverdueID '7a040000-0000-0000-0000-000000000007'
\set eventWithSessionsID '7a040000-0000-0000-0000-000000000008'
\set groupCategoryID '7a040000-0000-0000-0000-000000000009'
\set groupID '7a040000-0000-0000-0000-000000000010'
\set meetingEventCanceledID '7a040000-0000-0000-0000-000000000011'
\set meetingEventNotOverdueID '7a040000-0000-0000-0000-000000000012'
\set meetingEventOlderOverdueID '7a040000-0000-0000-0000-000000000013'
\set meetingEventProcessedID '7a040000-0000-0000-0000-000000000014'
\set meetingEventRecentOverdueID '7a040000-0000-0000-0000-000000000015'
\set meetingSessionOutOfSyncID '7a040000-0000-0000-0000-000000000016'
\set meetingSessionOverdueID '7a040000-0000-0000-0000-000000000017'
\set sessionOutOfSyncID '7a040000-0000-0000-0000-000000000018'
\set sessionOverdueID '7a040000-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event candidates and exclusions
select fx_event(:'eventRecentOverdueID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp - interval '25 minutes',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'slug', 'event-recent-overdue',
    'starts_at', current_timestamp - interval '1 hour'
));
select fx_event(:'eventOlderOverdueID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp - interval '90 minutes',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'slug', 'event-older-overdue',
    'starts_at', current_timestamp - interval '3 hours'
));
select fx_event(:'eventNotOverdueID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp - interval '5 minutes',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'slug', 'event-not-overdue',
    'starts_at', current_timestamp - interval '40 minutes'
));
select fx_event(:'eventProcessedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp - interval '40 minutes',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'starts_at', current_timestamp - interval '2 hours'
));
select fx_event(:'eventCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'capacity', 100,
    'ends_at', current_timestamp - interval '40 minutes',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', current_timestamp - interval '2 hours'
));
select fx_event(:'eventWithSessionsID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '2 hours',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'starts_at', current_timestamp - interval '2 hours'
));

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
    :'meetingEventRecentOverdueID',
    'zoom',
    'event-recent-overdue'
),
(
    null,
    null,
    :'eventOlderOverdueID',
    'https://zoom.us/j/event-older-overdue',
    :'meetingEventOlderOverdueID',
    'zoom',
    'event-older-overdue'
),
(
    null,
    null,
    :'eventNotOverdueID',
    'https://zoom.us/j/event-not-overdue',
    :'meetingEventNotOverdueID',
    'zoom',
    'event-not-overdue'
),
(
    current_timestamp - interval '1 minute',
    'auto_ended',
    :'eventProcessedID',
    'https://zoom.us/j/event-processed',
    :'meetingEventProcessedID',
    'zoom',
    'event-processed'
),
(
    null,
    null,
    :'eventCanceledID',
    'https://zoom.us/j/event-canceled',
    :'meetingEventCanceledID',
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
    :'meetingSessionOverdueID',
    'zoom',
    'session-overdue',
    :'sessionOverdueID'
),
(
    'https://zoom.us/j/session-out-of-sync',
    :'meetingSessionOutOfSyncID',
    'zoom',
    'session-out-of-sync',
    :'sessionOutOfSyncID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Returns and claims most recently overdue eligible event meeting first
select is(
    claim_meeting_for_auto_end() - 'auto_end_check_claimed_at' - 'meeting_id',
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
select claim_meeting_for_auto_end() as next_event_claim \gset
select is(
    (:'next_event_claim'::jsonb)->>'provider_meeting_id',
    'event-older-overdue',
    'Returns the next overdue event meeting after the first is checked'
);
select is(
    ((:'next_event_claim'::jsonb)->>'auto_end_check_claimed_at')::timestamptz,
    (select auto_end_check_claimed_at from meeting where provider_meeting_id = 'event-older-overdue'),
    'Returns the claim token stored on the claimed meeting'
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
