-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000001811'
\set communityID '00000000-0000-0000-0000-000000001801'
\set eventID '00000000-0000-0000-0000-000000001812'
\set groupCategoryID '00000000-0000-0000-0000-000000001810'
\set groupID '00000000-0000-0000-0000-000000001802'
\set sessionID '00000000-0000-0000-0000-000000001813'
\set userHostID '00000000-0000-0000-0000-000000001821'
\set userSpeakerID '00000000-0000-0000-0000-000000001822'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Users
insert into "user" (user_id, auth_hash, email, username) values
    (:'userHostID', 'hash-host', 'host@example.com', 'host'),
    (:'userSpeakerID', 'hash-speaker', 'speaker@example.com', 'speaker');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'categoryID', 'Conference', :'communityID');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, description)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group', 'A test group');

-- Parent event
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_provider_id,
    meeting_requested,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    100,
    'Parent event for session hash',
    '2026-06-01 12:00:00+00',
    :'categoryID',
    :'eventID',
    'virtual',
    :'groupID',
    'zoom',
    true,
    'Parent Event',
    true,
    'parent-event',
    '2026-06-01 10:00:00+00',
    'UTC'
);

-- Session hash target
insert into session (
    description,
    ends_at,
    event_id,
    meeting_hosts,
    meeting_provider_id,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    'Hash target session',
    '2026-06-01 10:30:00+00',
    :'eventID',
    array['explicit@example.com'],
    'zoom',
    true,
    'Hash Target Session',
    :'sessionID',
    'virtual',
    '2026-06-01 10:00:00+00'
);

-- Parent event host and session speaker are meeting sync inputs
insert into event_host (event_id, user_id)
values (:'eventID', :'userHostID');
insert into session_speaker (session_id, user_id, featured)
values (:'sessionID', :'userSpeakerID', false);

-- Hash captures
create temporary table session_sync_hash (
    label text primary key,
    sync_state_hash text not null
);

-- Capture hashes before and after changing an unrelated session field
insert into session_sync_hash (label, sync_state_hash)
values ('before_description_change', get_session_meeting_sync_state_hash(:'sessionID'));
update session
set description = 'Changed description'
where session_id = :'sessionID';
insert into session_sync_hash (label, sync_state_hash)
values ('after_description_change', get_session_meeting_sync_state_hash(:'sessionID'));

-- Capture hashes before and after changing the meeting payload
insert into session_sync_hash (label, sync_state_hash)
values ('before_name_change', get_session_meeting_sync_state_hash(:'sessionID'));
update session
set name = 'Changed Hash Target Session'
where session_id = :'sessionID';
insert into session_sync_hash (label, sync_state_hash)
values ('after_name_change', get_session_meeting_sync_state_hash(:'sessionID'));

-- Capture hashes before and after changing a parent event meeting input
insert into session_sync_hash (label, sync_state_hash)
values ('before_parent_event_change', get_session_meeting_sync_state_hash(:'sessionID'));
update event
set timezone = 'America/New_York'
where event_id = :'eventID';
insert into session_sync_hash (label, sync_state_hash)
values ('after_parent_event_change', get_session_meeting_sync_state_hash(:'sessionID'));

-- Capture hashes before and after changing session speakers
insert into session_sync_hash (label, sync_state_hash)
values ('before_session_speakers_change', get_session_meeting_sync_state_hash(:'sessionID'));
delete from session_speaker
where session_id = :'sessionID';
insert into session_sync_hash (label, sync_state_hash)
values ('after_session_speakers_change', get_session_meeting_sync_state_hash(:'sessionID'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return a hash for a session
select isnt(
    get_session_meeting_sync_state_hash(:'sessionID'),
    null,
    'Should return hash for existing session'
);

-- Changing unrelated session fields should not change the hash
select is(
    (select before.sync_state_hash = after.sync_state_hash
     from session_sync_hash before, session_sync_hash after
     where before.label = 'before_description_change'
       and after.label = 'after_description_change'),
    true,
    'Should keep same hash when unrelated session field changes'
);

-- Changing session payload fields should change the hash
select is(
    (select before.sync_state_hash <> after.sync_state_hash
     from session_sync_hash before, session_sync_hash after
     where before.label = 'before_name_change'
       and after.label = 'after_name_change'),
    true,
    'Should change hash when session meeting payload changes'
);

-- Changing parent event fields used by session meetings should change the hash
select is(
    (select before.sync_state_hash <> after.sync_state_hash
     from session_sync_hash before, session_sync_hash after
     where before.label = 'before_parent_event_change'
       and after.label = 'after_parent_event_change'),
    true,
    'Should change hash when parent event meeting input changes'
);

-- Changing session speakers should change the hash
select is(
    (select before.sync_state_hash <> after.sync_state_hash
     from session_sync_hash before, session_sync_hash after
     where before.label = 'before_session_speakers_change'
       and after.label = 'after_session_speakers_change'),
    true,
    'Should change hash when session speakers change'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
