-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000001711'
\set communityID '00000000-0000-0000-0000-000000001701'
\set eventID '00000000-0000-0000-0000-000000001712'
\set groupCategoryID '00000000-0000-0000-0000-000000001710'
\set groupID '00000000-0000-0000-0000-000000001702'
\set userHostID '00000000-0000-0000-0000-000000001721'
\set userSpeakerID '00000000-0000-0000-0000-000000001722'

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

-- Event hash target
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_hosts,
    meeting_provider_id,
    meeting_requested,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    100,
    'Hash target event',
    '2026-06-01 11:00:00+00',
    :'categoryID',
    :'eventID',
    'virtual',
    :'groupID',
    array['explicit@example.com'],
    'zoom',
    true,
    'Hash Target Event',
    true,
    'hash-target-event',
    '2026-06-01 10:00:00+00',
    'UTC'
);

-- Event host and speaker are meeting sync inputs
insert into event_host (event_id, user_id)
values (:'eventID', :'userHostID');
insert into event_speaker (event_id, user_id, featured)
values (:'eventID', :'userSpeakerID', false);

-- Hash captures
create temporary table event_sync_hash (
    label text primary key,
    sync_state_hash text not null
);

-- Capture hashes before and after changing an unrelated event field
insert into event_sync_hash (label, sync_state_hash)
values ('before_description_change', get_event_meeting_sync_state_hash(:'eventID'));
update event
set description = 'Changed description'
where event_id = :'eventID';
insert into event_sync_hash (label, sync_state_hash)
values ('after_description_change', get_event_meeting_sync_state_hash(:'eventID'));

-- Capture hashes before and after changing the meeting payload
insert into event_sync_hash (label, sync_state_hash)
values ('before_name_change', get_event_meeting_sync_state_hash(:'eventID'));
update event
set name = 'Changed Hash Target Event'
where event_id = :'eventID';
insert into event_sync_hash (label, sync_state_hash)
values ('after_name_change', get_event_meeting_sync_state_hash(:'eventID'));

-- Capture hashes before and after changing explicit meeting hosts
insert into event_sync_hash (label, sync_state_hash)
values ('before_meeting_hosts_change', get_event_meeting_sync_state_hash(:'eventID'));
update event
set meeting_hosts = array['explicit@example.com', 'new-host@example.com']
where event_id = :'eventID';
insert into event_sync_hash (label, sync_state_hash)
values ('after_meeting_hosts_change', get_event_meeting_sync_state_hash(:'eventID'));

-- Capture hashes before and after changing the recording preference
insert into event_sync_hash (label, sync_state_hash)
values ('before_recording_requested_change', get_event_meeting_sync_state_hash(:'eventID'));
update event
set meeting_recording_requested = false
where event_id = :'eventID';
insert into event_sync_hash (label, sync_state_hash)
values ('after_recording_requested_change', get_event_meeting_sync_state_hash(:'eventID'));

-- Capture hashes before and after changing event hosts
insert into event_sync_hash (label, sync_state_hash)
values ('before_event_hosts_change', get_event_meeting_sync_state_hash(:'eventID'));
delete from event_host
where event_id = :'eventID';
insert into event_sync_hash (label, sync_state_hash)
values ('after_event_hosts_change', get_event_meeting_sync_state_hash(:'eventID'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return a hash for an event
select isnt(
    get_event_meeting_sync_state_hash(:'eventID'),
    null,
    'Should return hash for existing event'
);

-- Changing unrelated event fields should not change the hash
select is(
    (select before.sync_state_hash = after.sync_state_hash
     from event_sync_hash before, event_sync_hash after
     where before.label = 'before_description_change'
       and after.label = 'after_description_change'),
    true,
    'Should keep same hash when unrelated event field changes'
);

-- Changing event payload fields should change the hash
select is(
    (select before.sync_state_hash <> after.sync_state_hash
     from event_sync_hash before, event_sync_hash after
     where before.label = 'before_name_change'
       and after.label = 'after_name_change'),
    true,
    'Should change hash when event meeting payload changes'
);

-- Changing explicit meeting hosts should change the hash
select is(
    (select before.sync_state_hash <> after.sync_state_hash
     from event_sync_hash before, event_sync_hash after
     where before.label = 'before_meeting_hosts_change'
       and after.label = 'after_meeting_hosts_change'),
    true,
    'Should change hash when explicit meeting hosts change'
);

-- Changing recording preference should change the hash
select is(
    (select before.sync_state_hash <> after.sync_state_hash
     from event_sync_hash before, event_sync_hash after
     where before.label = 'before_recording_requested_change'
       and after.label = 'after_recording_requested_change'),
    true,
    'Should change hash when event meeting recording preference changes'
);

-- Changing event hosts should change the hash
select is(
    (select before.sync_state_hash <> after.sync_state_hash
     from event_sync_hash before, event_sync_hash after
     where before.label = 'before_event_hosts_change'
       and after.label = 'after_event_hosts_change'),
    true,
    'Should change hash when event hosts change'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
