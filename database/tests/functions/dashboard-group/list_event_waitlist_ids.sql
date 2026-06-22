-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a1e0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a1e0000-0000-0000-0000-000000000002'
\set eventID '3a1e0000-0000-0000-0000-000000000003'
\set groupCategoryID '3a1e0000-0000-0000-0000-000000000004'
\set groupID '3a1e0000-0000-0000-0000-000000000005'
\set missingEventID '3a1e0000-0000-0000-0000-000000000006'
\set missingGroupID '3a1e0000-0000-0000-0000-000000000007'
\set otherGroupID '3a1e0000-0000-0000-0000-000000000008'
\set user0ID '3a1e0000-0000-0000-0000-000000000009'
\set user1ID '3a1e0000-0000-0000-0000-000000000010'
\set user2ID '3a1e0000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'test-alliance',
    'Test Alliance',
    'A test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

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
);

-- Groups
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values
    (:'groupID', :'allianceID', :'groupCategoryID', 'Test Group', 'test-group'),
    (:'otherGroupID', :'allianceID', :'groupCategoryID', 'Other Group', 'other-group');

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
    published,
    capacity,
    waitlist_enabled
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Test Event',
    'test-event',
    'Test event description',
    'UTC',
    true,
    1,
    true
);

-- Waitlist entries
insert into event_waitlist (event_id, user_id)
values
    (:'eventID', :'user0ID'),
    (:'eventID', :'user1ID'),
    (:'eventID', :'user2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return verified waitlist users only
select is(
    list_event_waitlist_ids(:'groupID'::uuid, :'eventID'::uuid),
    array[:'user0ID'::uuid, :'user1ID'::uuid],
    'Returns verified waitlist users only'
);

-- Should return empty list for event without waitlist entries
select is(
    list_event_waitlist_ids(:'missingGroupID'::uuid, :'missingEventID'::uuid),
    array[]::uuid[],
    'Returns empty list for event without waitlist entries'
);

-- Should return empty list when wrong group_id is provided
select is(
    list_event_waitlist_ids(:'otherGroupID'::uuid, :'eventID'::uuid),
    array[]::uuid[],
    'Returns empty list when wrong group_id is provided'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
