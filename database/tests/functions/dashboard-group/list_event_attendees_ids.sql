-- Tests listing verified confirmed attendee ids for an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a180000-0000-0000-0000-000000000001'
\set eventCategoryID '3a180000-0000-0000-0000-000000000002'
\set eventID '3a180000-0000-0000-0000-000000000003'
\set groupCategoryID '3a180000-0000-0000-0000-000000000004'
\set groupID '3a180000-0000-0000-0000-000000000005'
\set missingEventID '3a180000-0000-0000-0000-000000000006'
\set missingGroupID '3a180000-0000-0000-0000-000000000007'
\set otherGroupID '3a180000-0000-0000-0000-000000000008'
\set otherEventID '3a180000-0000-0000-0000-000000000013'
\set user0ID '3a180000-0000-0000-0000-000000000009'
\set user1ID '3a180000-0000-0000-0000-000000000010'
\set user2ID '3a180000-0000-0000-0000-000000000011'
\set user3ID '3a180000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user0ID');
select fx_user(:'user1ID');
select fx_user(:'user3ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user2ID', jsonb_build_object('email_verified', false));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Other event in the same group used to prove event isolation
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event attendees covering checked-in, pending, and unverified states
insert into event_attendee (checked_in, event_id, status, user_id)
values
    (false, :'eventID', 'confirmed', :'user0ID'),
    (true, :'eventID', 'confirmed', :'user1ID'),
    (true, :'eventID', 'confirmed', :'user2ID'),
    (true, :'eventID', 'invitation-pending', :'user3ID');

-- Other event attendee excluded from the primary event result set
insert into event_attendee (checked_in, event_id, status, user_id)
values (true, :'otherEventID', 'confirmed', :'user3ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return empty list for event without attendees
select is(
    list_event_attendees_ids(:'missingGroupID'::uuid, :'missingEventID'::uuid, false),
    array[]::uuid[],
    'Should return empty list for event without attendees'
);

-- Should return empty list when wrong group_id provided
select is(
    list_event_attendees_ids(:'otherGroupID'::uuid, :'eventID'::uuid, false),
    array[]::uuid[],
    'Should return empty list when wrong group_id provided'
);

-- Should return only checked-in verified confirmed attendees when filtered
select is(
    list_event_attendees_ids(:'groupID'::uuid, :'eventID'::uuid, true),
    array[:'user1ID'::uuid],
    'Should return only checked-in verified confirmed attendees when filtered'
);

-- Should return verified confirmed attendees ordered by user id
select is(
    list_event_attendees_ids(:'groupID'::uuid, :'eventID'::uuid, false),
    array[:'user0ID'::uuid, :'user1ID'::uuid],
    'Should return verified confirmed attendees ordered by user id'
);

-- Should isolate attendees to the requested event
select is(
    list_event_attendees_ids(:'groupID'::uuid, :'otherEventID'::uuid, false),
    array[:'user3ID'::uuid],
    'Should isolate attendees to the requested event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
