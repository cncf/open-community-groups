-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000211'
\set communityID '00000000-0000-0000-0000-000000000201'
\set eventID '00000000-0000-0000-0000-000000000212'
\set groupCategoryID '00000000-0000-0000-0000-000000000210'
\set groupID '00000000-0000-0000-0000-000000000202'
\set orphanMeetingID '00000000-0000-0000-0000-000000000214'
\set sessionID '00000000-0000-0000-0000-000000000213'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'categoryID', 'Conference', 'conference', :'communityID');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, description)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group', 'A test group');

-- Event
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    name,
    slug,
    timezone,
    description
) values (
    :'eventID',
    :'categoryID',
    'virtual',
    :'groupID',
    false,
    'Test Event',
    'test-event',
    'America/New_York',
    'A test event'
);

-- Session
insert into session (
    event_id,
    meeting_in_sync,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    :'eventID',
    false,
    'Test Session',
    :'sessionID',
    'virtual',
    '2025-06-01 10:00:00-04'
);

-- Orphan meeting
insert into meeting (meeting_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'orphanMeetingID', 'zoom', 'provider-001', 'https://zoom.us/j/provider-001');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set event error and sync flag for event meeting
select lives_ok(
    format(
        $$select set_meeting_error(%L::text, %L::uuid, null, null)$$,
        'event sync failed',
        :'eventID'
    ),
    'Should set event error and sync flag for event meeting'
);
select is(
    (select meeting_error from event where event_id = :'eventID'),
    'event sync failed',
    'Should persist event meeting_error'
);
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    true,
    'Should mark event as in sync'
);

-- Should set session error and sync flag for session meeting
select lives_ok(
    format(
        $$select set_meeting_error(%L::text, null, null, %L::uuid)$$,
        'session sync failed',
        :'sessionID'
    ),
    'Should set session error and sync flag for session meeting'
);
select is(
    (select meeting_error from session where session_id = :'sessionID'),
    'session sync failed',
    'Should persist session meeting_error'
);
select is(
    (select meeting_in_sync from session where session_id = :'sessionID'),
    true,
    'Should mark session as in sync'
);

-- Should delete orphan meeting when no event/session exists
select lives_ok(
    format(
        $$select set_meeting_error(%L::text, null, %L::uuid, null)$$,
        'orphan sync failed',
        :'orphanMeetingID'
    ),
    'Should delete orphan meeting when no event/session exists'
);
select is(
    (select count(*) from meeting where meeting_id = :'orphanMeetingID'),
    0::bigint,
    'Should remove orphan meeting record'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
