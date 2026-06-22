-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance2ID '9a030000-0000-0000-0000-000000000001'
\set allianceID '9a030000-0000-0000-0000-000000000002'
\set group1ID '9a030000-0000-0000-0000-000000000003'
\set group2ID '9a030000-0000-0000-0000-000000000004'
\set group3ID '9a030000-0000-0000-0000-000000000005'
\set group4ID '9a030000-0000-0000-0000-000000000006'
\set group5ID '9a030000-0000-0000-0000-000000000007'
\set group6ID '9a030000-0000-0000-0000-000000000008'
\set group7ID '9a030000-0000-0000-0000-000000000009'
\set group8ID '9a030000-0000-0000-0000-000000000010'
\set group9ID '9a030000-0000-0000-0000-000000000011'
\set group10ID '9a030000-0000-0000-0000-000000000012'
\set group11ID '9a030000-0000-0000-0000-000000000013'
\set groupCategory1ID '9a030000-0000-0000-0000-000000000014'
\set groupCategory2ID '9a030000-0000-0000-0000-000000000015'
\set region1ID '9a030000-0000-0000-0000-000000000016'
\set region2ID '9a030000-0000-0000-0000-000000000017'

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
    'site-recent-groups',
    'Site Recent Groups',
    'Alliance used for site recently added groups tests',
    'https://example.com/site-recent-groups-banner-mobile.png',
    'https://example.com/site-recent-groups-banner.png',
    'https://example.com/site-recent-groups-logo.png'
);

-- Inactive alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    active,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'alliance2ID',
    'inactive-site-recent-groups',
    'Inactive Site Recent Groups',
    'Inactive alliance used for site recently added groups tests',
    false,
    'https://example.com/inactive-site-recent-groups-banner-mobile.png',
    'https://example.com/inactive-site-recent-groups-banner.png',
    'https://example.com/inactive-site-recent-groups-logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values
    (:'groupCategory1ID', :'allianceID', 'Technology'),
    (:'groupCategory2ID', :'alliance2ID', 'Technology');

-- Region
insert into region (region_id, name, alliance_id)
values
    (:'region1ID', 'North America', :'allianceID'),
    (:'region2ID', 'Europe', :'allianceID');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    city,
    country_code,
    country_name,
    created_at,
    description,
    logo_url,
    region_id,
    state
)
values
    (:'group1ID', :'allianceID', :'groupCategory1ID', 'Test Group 1', 'abc1234',
        'New York', 'US', 'United States', '2024-01-01 09:00:00+00',
        'First group', 'https://example.com/logo1.png', :'region1ID', 'NY'),
    (:'group2ID', :'allianceID', :'groupCategory1ID', 'Test Group 2', 'def5678',
        'San Francisco', 'US', 'United States', '2024-01-02 09:00:00+00',
        'Second group', 'https://example.com/logo2.png', :'region1ID', 'CA'),
    (:'group3ID', :'allianceID', :'groupCategory1ID', 'Test Group 3', 'ghi9abc',
        'London', 'GB', 'United Kingdom', '2024-01-03 09:00:00+00',
        'Third group', 'https://example.com/logo3.png', :'region2ID', null),
    (:'group4ID', :'allianceID', :'groupCategory1ID', 'Test Group 4', 'jkl0def',
        'Paris', 'FR', 'France', '2024-01-04 09:00:00+00',
        'Fourth group (no logo)', null, :'region2ID', null),
    (:'group5ID', :'alliance2ID', :'groupCategory2ID', 'Inactive Alliance Group', 'mno1ghi',
        'Denver', 'US', 'United States', '2024-01-05 09:00:00+00',
        'Group in inactive alliance', 'https://example.com/logo5.png', null, 'CO'),
    (:'group6ID', :'allianceID', :'groupCategory1ID', 'Test Group 6', 'pqr2jkl',
        'Toronto', 'CA', 'Canada', '2024-01-06 09:00:00+00',
        'Sixth group', 'https://example.com/logo6.png', :'region1ID', 'ON'),
    (:'group7ID', :'allianceID', :'groupCategory1ID', 'Test Group 7', 'stu3mno',
        'Madrid', 'ES', 'Spain', '2024-01-07 09:00:00+00',
        'Seventh group', 'https://example.com/logo7.png', :'region2ID', null),
    (:'group8ID', :'allianceID', :'groupCategory1ID', 'Test Group 8', 'vwx4pqr',
        'Boston', 'US', 'United States', '2024-01-08 09:00:00+00',
        'Eighth group', 'https://example.com/logo8.png', :'region1ID', 'MA'),
    (:'group9ID', :'allianceID', :'groupCategory1ID', 'Test Group 9', 'yza5stu',
        'Rome', 'IT', 'Italy', '2024-01-09 09:00:00+00',
        'Ninth group', 'https://example.com/logo9.png', :'region2ID', null),
    (:'group10ID', :'allianceID', :'groupCategory1ID', 'Test Group 10', 'bcd6vwx',
        'Paris', 'FR', 'France', '2024-01-10 09:00:00+00',
        'Tenth group', 'https://example.com/logo10.png', :'region2ID', null),
    (:'group11ID', :'allianceID', :'groupCategory1ID', 'Test Group 11', 'efg7yza',
        'Seattle', 'US', 'United States', '2024-01-11 09:00:00+00',
        'Eleventh group', 'https://example.com/logo11.png', :'region1ID', 'WA');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return groups ordered by creation date DESC
select is(
    get_site_recently_added_groups()::jsonb,
    jsonb_build_array(
        get_group_summary(:'allianceID'::uuid, :'group11ID'::uuid)::jsonb,
        get_group_summary(:'allianceID'::uuid, :'group10ID'::uuid)::jsonb,
        get_group_summary(:'allianceID'::uuid, :'group9ID'::uuid)::jsonb,
        get_group_summary(:'allianceID'::uuid, :'group8ID'::uuid)::jsonb,
        get_group_summary(:'allianceID'::uuid, :'group7ID'::uuid)::jsonb,
        get_group_summary(:'allianceID'::uuid, :'group6ID'::uuid)::jsonb,
        get_group_summary(:'allianceID'::uuid, :'group4ID'::uuid)::jsonb,
        get_group_summary(:'allianceID'::uuid, :'group3ID'::uuid)::jsonb
    ),
    'Should return groups ordered by creation date DESC'
);

-- Should return at most eight groups
select is(
    jsonb_array_length(get_site_recently_added_groups()::jsonb),
    8,
    'Should return at most eight groups'
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
