-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventID '00000000-0000-0000-0000-000000000031'
\set eventNoMeetingID '00000000-0000-0000-0000-000000000032'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000021'
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
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

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

-- User (as previously published_by)
insert into "user" (
    user_id,
    auth_hash,
    email,
    username
) values (
    :'userID',
    'x',
    'user@test.local',
    'user'
);

-- Event (published, not canceled)
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

    canceled,
    capacity,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    published,
    published_at,
    published_by
) values (
    :'eventID',
    :'groupID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC',
    :'eventCategoryID',
    'virtual',
    now(),
    now() + interval '1 hour',

    false,
    100,
    true,
    'zoom',
    true,
    true,
    now(),
    :'userID'
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
    published,
    published_at,
    published_by,
    canceled
) values (
    :'eventNoMeetingID',
    :'groupID',
    'Test Event No Meeting',
    'test-event-no-meeting',
    'A test event without meeting',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now(),
    now() + interval '1 hour',
    null,
    false,
    true,
    now(),
    :'userID',
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
    now(),
    now() + interval '30 minutes',
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
    now() + interval '30 minutes',
    now() + interval '1 hour',
    'in-person',
    null,
    false
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mark as canceled and clear publication metadata
select lives_ok(
    $$select cancel_event('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'Should mark as canceled and clear publication metadata'
);

-- Should set canceled=true
select is(
    (select canceled from event where event_id = :'eventID'),
    true,
    'Should set canceled=true'
);

-- Should set published=false
select is(
    (select published from event where event_id = :'eventID'),
    false,
    'Should set published=false'
);

-- Should set published_at to null
select is(
    (select published_at from event where event_id = :'eventID'),
    null,
    'Should set published_at to null'
);

-- Should set published_by to null
select is(
    (select published_by from event where event_id = :'eventID'),
    null,
    'Should set published_by to null'
);

-- Should mark meeting_in_sync false when meeting was requested
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    false,
    'Should mark meeting_in_sync false when meeting was requested'
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

-- Should not change event meeting_in_sync when meeting_requested=false
select lives_ok(
    $$select cancel_event('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000032'::uuid)$$,
    'Should cancel event when meeting_requested=false'
);

-- Should keep event meeting_in_sync unchanged when meeting_requested=false
select is(
    (select meeting_in_sync from event where event_id = :'eventNoMeetingID'),
    null,
    'Should keep event meeting_in_sync unchanged when meeting_requested=false'
);

-- Should throw error when group_id does not match
select throws_ok(
    $$select cancel_event('00000000-0000-0000-0000-000000000099'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
