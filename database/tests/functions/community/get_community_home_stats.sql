-- Start transaction and plan tests
begin;
select plan(1);

-- Declare some variables
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
insert into "user" (user_id, email, community_id, created_at)
values
    (:'user1ID', 'user1@example.com', :'community1ID', '2024-01-01 00:00:00'),
    (:'user2ID', 'user2@example.com', :'community1ID', '2024-01-01 00:00:00');

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

-- Test get_community_home_stats function returns correct data
select is(
    get_community_home_stats('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
    '{
        "events": 1,
        "groups": 2,
        "groups_members": 0,
        "events_attendees": 0
    }'::jsonb,
    'get_community_home_stats should return correct stats as JSON'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;