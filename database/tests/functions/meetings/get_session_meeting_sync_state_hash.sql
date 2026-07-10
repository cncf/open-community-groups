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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Conference');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'userHostID', 'hash-host', 'host@example.com', true, 'host'),
    (:'userSpeakerID', 'hash-speaker', 'speaker@example.com', true, 'speaker');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'A test group'
);

-- Parent event
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    capacity,
    ends_at,
    meeting_provider_id,
    meeting_requested,
    published,
    starts_at,
    timezone
) values (
    :'eventID',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Parent Event',
    'parent-event',
    'Parent event for session hash',
    100,
    '2026-06-01 12:00:00+00',
    'zoom',
    true,
    true,
    '2026-06-01 10:00:00+00',
    'UTC'
);

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
