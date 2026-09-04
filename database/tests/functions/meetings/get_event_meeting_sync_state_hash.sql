-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a070000-0000-0000-0000-000000000001'
\set eventCategoryID '7a070000-0000-0000-0000-000000000002'
\set eventID '7a070000-0000-0000-0000-000000000003'
\set groupCategoryID '7a070000-0000-0000-0000-000000000004'
\set groupID '7a070000-0000-0000-0000-000000000005'
\set userHostID '7a070000-0000-0000-0000-000000000006'
\set userSpeakerID '7a070000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userSpeakerID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users with scenario-specific state
select fx_user(:'userHostID', jsonb_build_object(
    'email', 'host@example.com',
    'username', 'host'
));

-- Event hash target
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-01 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_hosts', array['explicit@example.com'],
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'name', 'Hash Target Event',
    'published', true,
    'starts_at', '2026-06-01 10:00:00+00'
));

-- Event host and speaker are meeting sync inputs
insert into event_host (event_id, user_id)
values (:'eventID', :'userHostID');

-- Event speaker included in the meeting sync hash
insert into event_speaker (event_id, user_id, featured)
values (:'eventID', :'userSpeakerID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return a hash for an event
select isnt(
    get_event_meeting_sync_state_hash(:'eventID'),
    null,
    'Should return hash for existing event'
);

-- Should keep the hash when an unrelated event field changes
select get_event_meeting_sync_state_hash(:'eventID') as "hashBefore" \gset

-- Change only a field intentionally excluded from the hash
update event
set description = 'Changed description'
where event_id = :'eventID';

select is(
    get_event_meeting_sync_state_hash(:'eventID'),
    :'hashBefore',
    'Should keep same hash when unrelated event field changes'
);

-- Should change the hash when an event meeting payload changes
select get_event_meeting_sync_state_hash(:'eventID') as "hashBefore" \gset

-- Change an event field included in the provider payload
update event
set name = 'Changed Hash Target Event'
where event_id = :'eventID';

select isnt(
    get_event_meeting_sync_state_hash(:'eventID'),
    :'hashBefore',
    'Should change hash when event meeting payload changes'
);

-- Should change the hash when explicit meeting hosts change
select get_event_meeting_sync_state_hash(:'eventID') as "hashBefore" \gset

-- Change the explicit meeting-host input included in the hash
update event
set meeting_hosts = array['explicit@example.com', 'new-host@example.com']
where event_id = :'eventID';

select isnt(
    get_event_meeting_sync_state_hash(:'eventID'),
    :'hashBefore',
    'Should change hash when explicit meeting hosts change'
);

-- Should change the hash when the recording preference changes
select get_event_meeting_sync_state_hash(:'eventID') as "hashBefore" \gset

-- Change the recording preference included in the provider payload
update event
set meeting_recording_requested = false
where event_id = :'eventID';

select isnt(
    get_event_meeting_sync_state_hash(:'eventID'),
    :'hashBefore',
    'Should change hash when event meeting recording preference changes'
);

-- Should change the hash when event hosts change
select get_event_meeting_sync_state_hash(:'eventID') as "hashBefore" \gset

-- Remove a related host included in the hash
delete from event_host
where event_id = :'eventID';

select isnt(
    get_event_meeting_sync_state_hash(:'eventID'),
    :'hashBefore',
    'Should change hash when event hosts change'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
