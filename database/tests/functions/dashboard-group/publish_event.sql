-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventID '00000000-0000-0000-0000-000000000031'
\set eventNoMeetingID '00000000-0000-0000-0000-000000000032'
\set eventNoStartDateID '00000000-0000-0000-0000-000000000033'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000021'
\set sessionMeetingID '00000000-0000-0000-0000-000000000051'
\set sessionNoMeetingID '00000000-0000-0000-0000-000000000052'
\set userID '00000000-0000-0000-0000-000000000041'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

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
insert into "user" (user_id, auth_hash, email, username)
values (:'userID', 'x', 'user@test.local', 'user');

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

    capacity,
    meeting_in_sync,
    meeting_provider_id,
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

    100,
    true,
    'zoom',
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
    current_timestamp + interval '12 hours',
    current_timestamp + interval '13 hours',
    null,
    false,
    false
);

-- Event without start date (to verify it cannot be published)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published
) values (
    :'eventNoStartDateID',
    :'groupID',
    'Test Event No Start Date',
    'test-event-no-start-date',
    'A test event without start date',
    'UTC',
    :'eventCategoryID',
    'in-person',
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
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionMeetingID',
    :'eventID',
    'Session With Meeting',
    '2025-06-01 10:00:00+00',
    '2025-06-01 10:30:00+00',
    'virtual',
    true,
    'zoom',
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

-- Should set published and metadata
select lives_ok(
    $$select publish_event('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, '00000000-0000-0000-0000-000000000041'::uuid)$$,
    'Should set published and metadata'
);

-- Should set published=true
select is(
    (select published from event where event_id = :'eventID'),
    true,
    'Should set published=true'
);

-- Should set published_at timestamp
select isnt(
    (select published_at from event where event_id = :'eventID'),
    null,
    'Should set published_at timestamp'
);

-- Should set published_by to the user
select is(
    (select published_by from event where event_id = :'eventID')::text,
    :'userID',
    'Should set published_by to the user'
);

-- Should set event meeting_in_sync to false
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    false,
    'Should set event meeting_in_sync=false'
);

-- Should set session meeting_in_sync to false when meeting_requested=true
select is(
    (select meeting_in_sync from session where session_id = :'sessionMeetingID'),
    false,
    'Should set session meeting_in_sync=false when meeting_requested=true'
);

-- Should not change session meeting_in_sync when meeting_requested=false
select is(
    (select meeting_in_sync from session where session_id = :'sessionNoMeetingID'),
    null,
    'Should not change session meeting_in_sync when meeting_requested=false'
);

-- Should publish event when meeting_requested=false
select lives_ok(
    $$select publish_event('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000032'::uuid, '00000000-0000-0000-0000-000000000041'::uuid)$$,
    'Should publish event when meeting_requested=false'
);

-- Should keep event meeting_in_sync unchanged when meeting_requested=false
select is(
    (select meeting_in_sync from event where event_id = :'eventNoMeetingID'),
    null,
    'Should keep event meeting_in_sync unchanged when meeting_requested=false'
);

-- Should mark reminder as evaluated when publishing event within 24 hours
select is(
    (select event_reminder_evaluated_for_starts_at from event where event_id = :'eventNoMeetingID'),
    (select starts_at from event where event_id = :'eventNoMeetingID'),
    'Should mark reminder as evaluated when publishing event within 24 hours'
);

-- Should throw error when group_id does not match
select throws_ok(
    $$select publish_event('00000000-0000-0000-0000-000000000099'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, '00000000-0000-0000-0000-000000000041'::uuid)$$,
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- Should throw error when event has no start date
select throws_ok(
    $$select publish_event('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000033'::uuid, '00000000-0000-0000-0000-000000000041'::uuid)$$,
    'event must have a start date to be published',
    'Should throw error when event has no start date'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
