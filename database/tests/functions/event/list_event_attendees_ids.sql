-- =============================================================================
-- SETUP
-- =============================================================================

begin;
select plan(4);

-- =============================================================================
-- VARIABLES
-- =============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set eventID '00000000-0000-0000-0000-000000000041'
\set user1ID '00000000-0000-0000-0000-000000000051'
\set user2ID '00000000-0000-0000-0000-000000000052'

-- =============================================================================
-- SEED DATA
-- =============================================================================

-- Community
insert into community (
    community_id,
    display_name,
    host,
    name,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'communityID', 'C1', 'c1.example.com', 'c1', 'C1', 'd',
    'https://e/logo.png', '{}'::jsonb
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'categoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'General', 'general', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users (u1 verified, u2 unverified)
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    name,
    username,
    email_verified
) values
    (:'user1ID', gen_random_bytes(32), :'communityID', 'u1@example.com', 'U1', 'u1', true),
    (:'user2ID', gen_random_bytes(32), :'communityID', 'u2@example.com', 'U2', 'u2', false);

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published
) values (
    :'eventID', 'Event', 'event', 'desc', 'UTC',
    :'eventCategoryID', 'in-person', :'groupID', true
);

-- Event attendees (include verified and unverified users)
insert into event_attendee (event_id, user_id)
values (:'eventID', :'user1ID'), (:'eventID', :'user2ID');

-- =============================================================================
-- TESTS
-- =============================================================================

-- Test: list_event_attendees_ids should return only verified users
select is(
    list_event_attendees_ids(:'groupID'::uuid, :'eventID'::uuid)::jsonb,
    json_build_array(:'user1ID'::uuid)::jsonb,
    'Returns verified attendees only'
);

-- Test: ordering is by user_id asc
-- Add a second verified user with lower id and ensure order asc
\set user0ID '00000000-0000-0000-0000-000000000050'
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    username,
    email_verified
) values (:'user0ID', gen_random_bytes(32), :'communityID', 'u0@example.com', 'u0', true);
insert into event_attendee (event_id, user_id) values (:'eventID', :'user0ID');
select is(
    list_event_attendees_ids(:'groupID'::uuid, :'eventID'::uuid)::jsonb,
    json_build_array(:'user0ID'::uuid, :'user1ID'::uuid)::jsonb,
    'Returns attendees ordered by user id asc'
);

-- Test: empty event should return empty array
select is(
    list_event_attendees_ids('00000000-0000-0000-0000-000000000030'::uuid, '00000000-0000-0000-0000-000000000099'::uuid)::text,
    '[]',
    'Returns empty list for event without attendees'
);

-- Test: wrong group_id should return empty array
-- Create another group and verify attendees are not returned when queried with wrong group_id
\set anotherGroupID '00000000-0000-0000-0000-000000000031'
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'anotherGroupID', :'communityID', :'categoryID', 'G2', 'g2');

select is(
    list_event_attendees_ids(:'anotherGroupID'::uuid, :'eventID'::uuid)::text,
    '[]',
    'Returns empty list when wrong group_id is provided'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

select * from finish();
rollback;

