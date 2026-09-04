-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a080000-0000-0000-0000-000000000001'
\set eventCategoryID '7a080000-0000-0000-0000-000000000002'
\set eventID '7a080000-0000-0000-0000-000000000003'
\set groupCategoryID '7a080000-0000-0000-0000-000000000004'
\set groupID '7a080000-0000-0000-0000-000000000005'
\set sessionID '7a080000-0000-0000-0000-000000000006'
\set userHostID '7a080000-0000-0000-0000-000000000007'
\set userSpeakerID '7a080000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userHostID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

select fx_user(:'userSpeakerID', jsonb_build_object('username', 'speaker'));

-- Parent event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-01 12:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'starts_at', '2026-06-01 10:00:00+00'
));

-- Session hash target
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    description,
    ends_at,
    meeting_hosts,
    meeting_provider_id,
    meeting_requested,
    starts_at
) values (
    :'sessionID',
    :'eventID',
    'Hash Target Session',
    'virtual',
    'Hash target session',
    '2026-06-01 10:30:00+00',
    array['explicit@example.com'],
    'zoom',
    true,
    '2026-06-01 10:00:00+00'
);

-- Parent event host and session speaker are meeting sync inputs
insert into event_host (event_id, user_id)
values (:'eventID', :'userHostID');

-- Session speaker included in the meeting sync hash
insert into session_speaker (session_id, user_id, featured)
values (:'sessionID', :'userSpeakerID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return a hash for a session
select isnt(
    get_session_meeting_sync_state_hash(:'sessionID'),
    null,
    'Should return hash for existing session'
);

-- Should keep the hash when an unrelated session field changes
select get_session_meeting_sync_state_hash(:'sessionID') as "hashBefore" \gset

-- Change only a field intentionally excluded from the hash
update session
set description = 'Changed description'
where session_id = :'sessionID';

select is(
    get_session_meeting_sync_state_hash(:'sessionID'),
    :'hashBefore',
    'Should keep same hash when unrelated session field changes'
);

-- Should change the hash when a session meeting payload changes
select get_session_meeting_sync_state_hash(:'sessionID') as "hashBefore" \gset

-- Change a session field included in the provider payload
update session
set name = 'Changed Hash Target Session'
where session_id = :'sessionID';

select isnt(
    get_session_meeting_sync_state_hash(:'sessionID'),
    :'hashBefore',
    'Should change hash when session meeting payload changes'
);

-- Should change the hash when a parent event meeting input changes
select get_session_meeting_sync_state_hash(:'sessionID') as "hashBefore" \gset

-- Change the parent timezone included in the session provider payload
update event
set timezone = 'America/New_York'
where event_id = :'eventID';

select isnt(
    get_session_meeting_sync_state_hash(:'sessionID'),
    :'hashBefore',
    'Should change hash when parent event meeting input changes'
);

-- Should change the hash when the parent recording preference changes
select get_session_meeting_sync_state_hash(:'sessionID') as "hashBefore" \gset

-- Change the parent recording preference inherited by session meetings
update event
set meeting_recording_requested = false
where event_id = :'eventID';

select isnt(
    get_session_meeting_sync_state_hash(:'sessionID'),
    :'hashBefore',
    'Should change hash when parent event meeting recording preference changes'
);

-- Should change the hash when session speakers change
select get_session_meeting_sync_state_hash(:'sessionID') as "hashBefore" \gset

-- Remove a related speaker included in the hash
delete from session_speaker
where session_id = :'sessionID';

select isnt(
    get_session_meeting_sync_state_hash(:'sessionID'),
    :'hashBefore',
    'Should change hash when session speakers change'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
