-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set group4ID '00000000-0000-0000-0000-000000000034'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set region2ID '00000000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A test community',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'communityID');

-- Region
insert into region (region_id, name, community_id)
values
    (:'region1ID', 'North America', :'communityID'),
    (:'region2ID', 'Europe', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, created_at, logo_url, description,
                     city, state, country_code, country_name, region_id)
values
    (:'group1ID', 'Test Group 1', 'abc1234', :'communityID', :'category1ID',
     '2024-01-01 09:00:00+00', 'https://example.com/logo1.png', 'First group',
     'New York', 'NY', 'US', 'United States', :'region1ID'),
    (:'group2ID', 'Test Group 2', 'def5678', :'communityID', :'category1ID',
     '2024-01-02 09:00:00+00', 'https://example.com/logo2.png', 'Second group',
     'San Francisco', 'CA', 'US', 'United States', :'region1ID'),
    (:'group3ID', 'Test Group 3', 'ghi9abc', :'communityID', :'category1ID',
     '2024-01-03 09:00:00+00', 'https://example.com/logo3.png', 'Third group',
     'London', null, 'GB', 'United Kingdom', :'region2ID'),
    (:'group4ID', 'Test Group 4', 'jkl0def', :'communityID', :'category1ID',
     '2024-01-04 09:00:00+00', null, 'Fourth group (no logo)',
     'Paris', null, 'FR', 'France', :'region2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude groups without logo_url
select is(
    get_site_recently_added_groups()::jsonb,
    jsonb_build_array(
        get_group_summary(:'communityID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group1ID'::uuid)::jsonb
    ),
    'Should exclude groups without logo_url'
);

-- Should return groups ordered by creation date DESC
delete from "group" where group_id = :'group4ID';
select is(
    get_site_recently_added_groups()::jsonb,
    jsonb_build_array(
        get_group_summary(:'communityID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group1ID'::uuid)::jsonb
    ),
    'Should return groups ordered by creation date DESC'
);

-- Should return empty array when no groups exist
delete from "group";
select is(
    get_site_recently_added_groups()::jsonb,
    '[]'::jsonb,
    'Should return empty array when no groups exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
