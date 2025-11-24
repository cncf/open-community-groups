-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set eventID '00000000-0000-0000-0000-000000000031'
\set eventNoMeetingID '00000000-0000-0000-0000-000000000032'
\set sessionMeetingID '00000000-0000-0000-0000-000000000051'
\set sessionNoMeetingID '00000000-0000-0000-0000-000000000052'
\set userID '00000000-0000-0000-0000-000000000041'

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
    'test.localhost',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'General', 'general', :'communityID');

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

-- User (publisher)
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    username
) values (
    :'userID',
    'x',
    :'communityID',
    'user@test.local',
    'user'
);

-- Event (unpublished, with meeting_in_sync=true to verify it gets set to false)
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
    meeting_requested,
    published
) values (
    :'eventID',
    :'groupID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC',
    :'eventCategoryID',
    'virtual',
    '2025-06-01 10:00:00+00',
    '2025-06-01 11:00:00+00',
    true,
    true,
    false
);

-- Event without meeting_requested (to verify meeting_in_sync is not changed)
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
    meeting_requested,
    published
) values (
    :'eventNoMeetingID',
    :'groupID',
    'Test Event No Meeting',
    'test-event-no-meeting',
    'A test event without meeting',
    'UTC',
    :'eventCategoryID',
    'in-person',
    '2025-06-02 10:00:00+00',
    '2025-06-02 11:00:00+00',
    null,
    false,
    false
);

-- Session with meeting_requested=true (should be marked as out of sync)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_requested
) values (
    :'sessionMeetingID',
    :'eventID',
    'Session With Meeting',
    '2025-06-01 10:00:00+00',
    '2025-06-01 10:30:00+00',
    'virtual',
    true,
    true
);

-- Session with meeting_requested=false (should NOT be marked as out of sync)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_requested
) values (
    :'sessionNoMeetingID',
    :'eventID',
    'Session Without Meeting',
    '2025-06-01 10:30:00+00',
    '2025-06-01 11:00:00+00',
    'in-person',
    null,
    false
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: publish_event should set published and metadata
select publish_event(:'groupID'::uuid, :'eventID'::uuid, :'userID'::uuid);

select is(
    (select published from event where event_id = :'eventID'),
    true,
    'publish_event should set published=true'
);

select isnt(
    (select published_at from event where event_id = :'eventID'),
    null,
    'publish_event should set published_at timestamp'
);

select is(
    (select published_by from event where event_id = :'eventID')::text,
    :'userID',
    'publish_event should set published_by to the user'
);

-- Test: publish_event should set event meeting_in_sync to false
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    false,
    'publish_event should set event meeting_in_sync=false'
);

-- Test: publish_event should set session meeting_in_sync to false when meeting_requested=true
select is(
    (select meeting_in_sync from session where session_id = :'sessionMeetingID'),
    false,
    'publish_event should set session meeting_in_sync=false when meeting_requested=true'
);

-- Test: publish_event should NOT change session meeting_in_sync when meeting_requested=false
select is(
    (select meeting_in_sync from session where session_id = :'sessionNoMeetingID'),
    null,
    'publish_event should not change session meeting_in_sync when meeting_requested=false'
);

-- Test: publish_event should NOT change event meeting_in_sync when meeting_requested=false
select publish_event(:'groupID'::uuid, :'eventNoMeetingID'::uuid, :'userID'::uuid);
select is(
    (select meeting_in_sync from event where event_id = :'eventNoMeetingID'),
    null,
    'publish_event should not change event meeting_in_sync when meeting_requested=false'
);

-- Test: publish_event should throw error when group_id does not match
select throws_ok(
    $$select publish_event('00000000-0000-0000-0000-000000000099'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, '00000000-0000-0000-0000-000000000041'::uuid)$$,
    'P0001',
    'event not found or inactive',
    'publish_event should throw error when group_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;

