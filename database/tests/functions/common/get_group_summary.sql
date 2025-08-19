-- Start transaction and plan tests
begin;
select plan(3);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set region1ID '00000000-0000-0000-0000-000000000012'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set groupInactiveID '00000000-0000-0000-0000-000000000022'

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
    'A test community for testing purposes',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Seed region
insert into region (region_id, name, community_id)
values (:'region1ID', 'North America', :'community1ID');

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Seed active group with all fields
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    region_id,
    active,
    city,
    state,
    country_code,
    country_name,
    logo_url,
    created_at
) values (
    :'group1ID',
    'Test Group',
    'test-group',
    :'community1ID',
    :'category1ID',
    :'region1ID',
    true,
    'New York',
    'NY',
    'US',
    'United States',
    'https://example.com/group-logo.png',
    '2024-01-15 10:00:00+00'
);

-- Seed inactive group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active,
    created_at
) values (
    :'groupInactiveID',
    'Inactive Group',
    'inactive-group',
    :'community1ID',
    :'category1ID',
    false,
    '2024-02-15 10:00:00+00'
);

-- Seed deleted group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active,
    deleted,
    deleted_at,
    created_at
) values (
    '00000000-0000-0000-0000-000000000023'::uuid,
    'Deleted Group',
    'deleted-group',
    :'community1ID',
    :'category1ID',
    false,
    true,
    '2024-03-15 10:00:00+00',
    '2024-02-15 10:00:00+00'
);

-- Test: get_group_summary function returns correct data
select is(
    get_group_summary('00000000-0000-0000-0000-000000000021'::uuid)::jsonb,
    '{
        "category": {
            "group_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "created_at": 1705312800,
        "group_id": "00000000-0000-0000-0000-000000000021",
        "name": "Test Group",
        "slug": "test-group",
        "city": "New York",
        "country_code": "US",
        "country_name": "United States",
        "logo_url": "https://example.com/group-logo.png",
        "region": {
            "region_id": "00000000-0000-0000-0000-000000000012",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "state": "NY"
    }'::jsonb,
    'get_group_summary should return correct group summary data as JSON'
);

-- Test: get_group_summary with non-existent group ID
select ok(
    get_group_summary('00000000-0000-0000-0000-000000999999'::uuid) is null,
    'get_group_summary with non-existent group ID should return null'
);

-- Test: get_group_summary with deleted group ID returns data
select ok(
    get_group_summary('00000000-0000-0000-0000-000000000023'::uuid) is not null,
    'get_group_summary with deleted group ID should return data'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;
