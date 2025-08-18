-- Start transaction and plan tests
begin;
select plan(2);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set user1ID '00000000-0000-0000-0000-000000000041'
\set user2ID '00000000-0000-0000-0000-000000000042'
\set event1ID '00000000-0000-0000-0000-000000000051'

-- Seed community
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
    :'community1ID',
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Seed groups
insert into "group" (group_id, name, slug, community_id, group_category_id)
values
    (:'group1ID', 'Test Group 1', 'test-group-1', :'community1ID', :'category1ID'),
    (:'group2ID', 'Test Group 2', 'test-group-2', :'community1ID', :'category1ID');

-- Seed users
insert into "user" (user_id, email, username, name, email_verified, auth_hash, community_id, created_at)
values
    (:'user1ID', 'user1@example.com', 'user1', 'User One', false, 'test_hash'::bytea, :'community1ID', '2024-01-01 00:00:00'),
    (:'user2ID', 'user2@example.com', 'user2', 'User Two', false, 'test_hash'::bytea, :'community1ID', '2024-01-01 00:00:00');

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values ('00000000-0000-0000-0000-000000000061', 'Tech Talks', 'tech-talks', :'community1ID');

-- Seed event
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
    :'event1ID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC',
    '00000000-0000-0000-0000-000000000061',
    'in-person',
    :'group1ID',
    true
);

-- Add group members
insert into group_member (group_id, user_id, created_at)
values
    (:'group1ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group1ID', :'user2ID', '2024-01-01 00:00:00'),
    (:'group2ID', :'user1ID', '2024-01-01 00:00:00');

-- Add event attendees
insert into event_attendee (event_id, user_id, created_at)
values
    (:'event1ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'event1ID', :'user2ID', '2024-01-01 00:00:00');

-- Test: get_community_home_stats function returns correct data
select is(
    get_community_home_stats('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
    '{
        "events": 1,
        "groups": 2,
        "groups_members": 3,
        "events_attendees": 2
    }'::jsonb,
    'get_community_home_stats should return correct stats as JSON'
);

-- Test: get_community_home_stats with non-existing community
select is(
    get_community_home_stats('00000000-0000-0000-0000-999999999999'::uuid)::jsonb,
    '{
        "events": 0,
        "groups": 0,
        "groups_members": 0,
        "events_attendees": 0
    }'::jsonb,
    'get_community_home_stats with non-existing community should return zeros'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;