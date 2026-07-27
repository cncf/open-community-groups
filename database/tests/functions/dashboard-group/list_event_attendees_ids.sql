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
    'Test community description',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'user0ID',
    gen_random_bytes(32),
    'u0@example.com',
    true,
    'u0',
    'U0'
), (
    :'user1ID',
    gen_random_bytes(32),
    'u1@example.com',
    true,
    'u1',
    'U1'
), (
    :'user2ID',
    gen_random_bytes(32),
    'u2@example.com',
    false,
    'u2',
    'U2'
), (
    :'user3ID',
    gen_random_bytes(32),
    'u3@example.com',
    true,
    'u3',
    'U3'
);

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group'),
    (:'otherGroupID', :'communityID', :'groupCategoryID', 'Other Group', 'other-group');

-- Event
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    published
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Test Event',
    'test-event',
    'Test event description',
    'UTC',
    true
);

-- Other event in the same group used to prove event isolation
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    published
) values (
    :'otherEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Other Test Event',
    'other-test-event',
    'Other test event description',
    'UTC',
    true
);

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
