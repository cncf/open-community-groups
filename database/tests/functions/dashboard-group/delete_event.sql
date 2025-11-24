-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000002'
\set eventID '00000000-0000-0000-0000-000000000003'
\set eventNoMeetingID '00000000-0000-0000-0000-000000000004'
\set sessionMeetingID '00000000-0000-0000-0000-000000000051'
\set sessionNoMeetingID '00000000-0000-0000-0000-000000000052'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'

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
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'seattle.cloudnative.org',
    'Cloud Native Seattle Community',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'categoryID', 'Conference', 'conference', :'communityID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

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
    'Kubernetes Study Group',
    'kubernetes-study-group',
    'A study group focused on Kubernetes best practices and implementation',
    :'groupCategoryID'
);

-- Event
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
    meeting_requested,
    meeting_in_sync,
    published
) values (
    :'eventID',
    :'groupID',
    'Container Security Workshop',
    'container-security-workshop',
    'Deep dive into container security best practices and threat mitigation',
    'America/New_York',
    :'categoryID',
    'virtual',
    now(),
    now() + interval '1 hour',
    true,
    true,
    true
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
    'Event No Meeting',
    'event-no-meeting',
    'An event without meeting requested',
    'America/New_York',
    :'categoryID',
    'in-person',
    now(),
    now() + interval '1 hour',
    null,
    false,
    true
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
    now(),
    now() + interval '30 minutes',
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
    now() + interval '30 minutes',
    now() + interval '1 hour',
    'in-person',
    null,
    false
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: delete_event should set deleted=true
select delete_event(:'groupID'::uuid, :'eventID'::uuid);
select is(
    (select deleted from event where event_id = :'eventID'),
    true,
    'delete_event should set deleted=true'
);

-- Test: delete_event should set deleted_at timestamp
select isnt(
    (select deleted_at from event where event_id = :'eventID'),
    null,
    'delete_event should set deleted_at timestamp'
);

-- Test: delete_event should set published=false
select is(
    (select published from event where event_id = :'eventID'),
    false,
    'delete_event should set published=false'
);

-- Test: delete_event should set meeting_in_sync=false
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    false,
    'delete_event should mark meeting_in_sync false when meeting was requested'
);

-- Test: delete_event should set session meeting_in_sync to false when meeting_requested=true
select is(
    (select meeting_in_sync from session where session_id = :'sessionMeetingID'),
    false,
    'delete_event should set session meeting_in_sync=false when meeting_requested=true'
);

-- Test: delete_event should NOT change session meeting_in_sync when meeting_requested=false
select is(
    (select meeting_in_sync from session where session_id = :'sessionNoMeetingID'),
    null,
    'delete_event should not change session meeting_in_sync when meeting_requested=false'
);

-- Test: delete_event should NOT change event meeting_in_sync when meeting_requested=false
select delete_event(:'groupID'::uuid, :'eventNoMeetingID'::uuid);
select is(
    (select meeting_in_sync from event where event_id = :'eventNoMeetingID'),
    null,
    'delete_event should not change event meeting_in_sync when meeting_requested=false'
);

-- Test: event should still exist in database (soft delete)
select is(
    (select count(*)::int from event where event_id = :'eventID'),
    1,
    'delete_event should keep event in database (soft delete)'
);

-- Test: delete_event should throw error when group_id does not match
select throws_ok(
    $$select delete_event('00000000-0000-0000-0000-000000000099'::uuid, '00000000-0000-0000-0000-000000000003'::uuid)$$,
    'P0001',
    'event not found or inactive',
    'delete_event should throw error when group_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
