-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set allianceID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set group4ID '00000000-0000-0000-0000-000000000034'
\set group5ID '00000000-0000-0000-0000-000000000035'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set region2ID '00000000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'allianceID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A test alliance',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Inactive alliance
insert into alliance (
    alliance_id,
    active,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'alliance2ID',
    false,
    'inactive-alliance',
    'Inactive Alliance',
    'An inactive test alliance',
    'https://example.com/logo2.png',
    'https://example.com/banner_mobile2.png',
    'https://example.com/banner2.png'
);

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values
    (:'category1ID', 'Technology', :'allianceID'),
    (:'category2ID', 'Technology', :'alliance2ID');

-- Region
insert into region (region_id, name, alliance_id)
values
    (:'region1ID', 'North America', :'allianceID'),
    (:'region2ID', 'Europe', :'allianceID');

-- Group
insert into "group" (group_id, name, slug, alliance_id, group_category_id, created_at, logo_url, description,
                     city, state, country_code, country_name, region_id)
values
    (:'group1ID', 'Test Group 1', 'abc1234', :'allianceID', :'category1ID',
     '2024-01-01 09:00:00+00', 'https://example.com/logo1.png', 'First group',
     'New York', 'NY', 'US', 'United States', :'region1ID'),
    (:'group2ID', 'Test Group 2', 'def5678', :'allianceID', :'category1ID',
     '2024-01-02 09:00:00+00', 'https://example.com/logo2.png', 'Second group',
     'San Francisco', 'CA', 'US', 'United States', :'region1ID'),
    (:'group3ID', 'Test Group 3', 'ghi9abc', :'allianceID', :'category1ID',
     '2024-01-03 09:00:00+00', 'https://example.com/logo3.png', 'Third group',
     'London', null, 'GB', 'United Kingdom', :'region2ID'),
    (:'group4ID', 'Test Group 4', 'jkl0def', :'allianceID', :'category1ID',
     '2024-01-04 09:00:00+00', null, 'Fourth group (no logo)',
     'Paris', null, 'FR', 'France', :'region2ID'),
    (:'group5ID', 'Inactive Alliance Group', 'mno1ghi', :'alliance2ID', :'category2ID',
     '2024-01-05 09:00:00+00', 'https://example.com/logo5.png', 'Group in inactive alliance',
     'Denver', 'CO', 'US', 'United States', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return groups ordered by creation date DESC
select is(
    get_site_recently_added_groups()::jsonb,
    jsonb_build_array(
        get_group_summary(:'allianceID'::uuid, :'group4ID'::uuid)::jsonb,
        get_group_summary(:'allianceID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'allianceID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'allianceID'::uuid, :'group1ID'::uuid)::jsonb
    ),
    'Should return groups ordered by creation date DESC'
);

-- Should not include groups from inactive alliances
select ok(
    not exists (
        select 1
        from jsonb_array_elements(get_site_recently_added_groups()::jsonb) as g
        where g->>'group_id' = :'group5ID'
    ),
    'Should not include groups from inactive alliances'
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
