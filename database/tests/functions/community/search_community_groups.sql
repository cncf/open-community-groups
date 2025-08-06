-- Start transaction and plan tests
begin;
select plan(1);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'

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

-- Seed group categories
insert into group_category (group_category_id, name, community_id)
values 
    (:'category1ID', 'Technology', :'community1ID'),
    (:'category2ID', 'Business', :'community1ID');

-- Seed region
insert into region (region_id, name, community_id)
values (:'region1ID', 'North America', :'community1ID');

-- Seed groups with different attributes
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    tags,
    city,
    country_name,
    region_id,
    location
) values
    (:'group1ID', 'Kubernetes Meetup', 'kubernetes-meetup', :'community1ID', :'category1ID',
     array['kubernetes', 'cloud'], 'San Francisco', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-122.4194 37.7749)')),
    (:'group2ID', 'Docker Users', 'docker-users', :'community1ID', :'category1ID',
     array['docker', 'containers'], 'New York', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-74.0060 40.7128)')),
    (:'group3ID', 'Business Leaders', 'business-leaders', :'community1ID', :'category2ID',
     array['leadership', 'management'], 'London', 'United Kingdom', null,
     ST_GeogFromText('POINT(-0.1278 51.5074)'));

-- Test search without filters returns all groups
select is(
    (select total from search_community_groups('00000000-0000-0000-0000-000000000001'::uuid, '{}'::jsonb)),
    3::bigint,
    'search_community_groups without filters should return all active groups'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;