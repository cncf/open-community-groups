-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

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

-- Event attendees
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'user1ID', 'confirmed'),
    (:'eventID', :'user2ID', 'confirmed'),
    (:'eventID', :'user3ID', 'invitation-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only verified confirmed attendees
select is(
    list_event_attendees_ids(:'groupID'::uuid, :'eventID'::uuid),
    array[:'user1ID'::uuid],
    'Returns verified confirmed attendees only'
);

-- Should return attendees ordered by user_id asc
-- Intentional mid-test seed: user0 must not exist for the previous test,
-- and is added here to verify ascending user_id ordering
insert into "user" (user_id, auth_hash, email, username, email_verified)
values (:'user0ID', gen_random_bytes(32), 'u0@example.com', 'u0', true);
insert into event_attendee (event_id, user_id) values (:'eventID', :'user0ID');
select is(
    list_event_attendees_ids(:'groupID'::uuid, :'eventID'::uuid),
    array[:'user0ID'::uuid, :'user1ID'::uuid],
    'Returns attendees ordered by user id asc'
);

-- Should return empty list for event without attendees
select is(
    list_event_attendees_ids(:'missingGroupID'::uuid, :'missingEventID'::uuid),
    array[]::uuid[],
    'Returns empty list for event without attendees'
);

-- Should return empty list when wrong group_id provided
select is(
    list_event_attendees_ids(:'otherGroupID'::uuid, :'eventID'::uuid),
    array[]::uuid[],
    'Returns empty list when wrong group_id is provided'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
