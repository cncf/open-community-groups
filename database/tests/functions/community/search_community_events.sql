-- Start transaction and plan tests
begin;
select plan(1);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'

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

-- Seed group
insert into "group" (group_id, name, slug, community_id, group_category_id)
values (:'group1ID', 'Test Group', 'test-group', :'community1ID', :'category1ID');

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'community1ID');

-- Seed events with different attributes
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    tags,
    venue_city
) values
    (:'event1ID', 'Kubernetes Workshop', 'kubernetes-workshop', 'Learn Kubernetes', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     '2026-02-01 10:00:00', array['kubernetes', 'cloud'], 'San Francisco'),
    (:'event2ID', 'Docker Training', 'docker-training', 'Docker fundamentals', 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     '2026-02-02 10:00:00', array['docker', 'containers'], 'New York'),
    (:'event3ID', 'Cloud Summit', 'cloud-summit', 'Annual cloud conference', 'UTC',
     :'eventCategory1ID', 'hybrid', :'group1ID', true,
     '2026-02-03 10:00:00', array['cloud', 'aws'], 'London');

-- Test search without filters returns all events
select is(
    (select total from search_community_events('00000000-0000-0000-0000-000000000001'::uuid, '{}'::jsonb)),
    3::bigint,
    'search_community_events without filters should return all published events'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;