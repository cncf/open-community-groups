-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0d030000-0000-0000-0000-000000000001'
\set groupCategoryID '0d030000-0000-0000-0000-000000000002'
\set group1ID '0d030000-0000-0000-0000-000000000003'
\set group2ID '0d030000-0000-0000-0000-000000000004'
\set group3ID '0d030000-0000-0000-0000-000000000005'
\set group4ID '0d030000-0000-0000-0000-000000000006'
\set group5ID '0d030000-0000-0000-0000-000000000007'
\set group6ID '0d030000-0000-0000-0000-000000000008'
\set group7ID '0d030000-0000-0000-0000-000000000009'
\set group8ID '0d030000-0000-0000-0000-000000000010'
\set group9ID '0d030000-0000-0000-0000-000000000011'
\set group10ID '0d030000-0000-0000-0000-000000000012'
\set groupInactiveID '0d030000-0000-0000-0000-000000000013'
\set region1ID '0d030000-0000-0000-0000-000000000014'
\set region2ID '0d030000-0000-0000-0000-000000000015'
\set unknownCommunityID '0d030000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'community-recent-groups',
    'Community Recent Groups',
    'Community used for recently added groups tests',
    'https://example.com/community-recent-groups-banner-mobile.png',
    'https://example.com/community-recent-groups-banner.png',
    'https://example.com/community-recent-groups-logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Region
insert into region (region_id, name, community_id)
values
    (:'region1ID', 'North America', :'communityID'),
    (:'region2ID', 'Europe', :'communityID');

-- Group
insert into "group" (
    group_id,
    community_id,
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
    (:'group1ID', :'communityID', :'groupCategoryID', 'Test Group 1', 'abc1234',
        'New York', 'US', 'United States', '2024-01-01 09:00:00+00',
        'First group', 'https://example.com/logo1.png', :'region1ID', 'NY'),
    (:'group2ID', :'communityID', :'groupCategoryID', 'Test Group 2', 'def5678',
        'San Francisco', 'US', 'United States', '2024-01-02 09:00:00+00',
        'Second group', 'https://example.com/logo2.png', :'region1ID', 'CA'),
    (:'group3ID', :'communityID', :'groupCategoryID', 'Test Group 3', 'ghi9abc',
        'London', 'GB', 'United Kingdom', '2024-01-03 09:00:00+00',
        'Third group', 'https://example.com/logo3.png', :'region2ID', null),
    (:'group4ID', :'communityID', :'groupCategoryID', 'Test Group 4', 'jkl0def',
        'Paris', 'FR', 'France', '2024-01-04 09:00:00+00',
        'Fourth group (no logo)', null, :'region2ID', null),
    (:'group5ID', :'communityID', :'groupCategoryID', 'Test Group 5', 'mno1ghi',
        'Berlin', 'DE', 'Germany', '2024-01-05 09:00:00+00',
        'Fifth group', 'https://example.com/logo5.png', :'region2ID', null),
    (:'group6ID', :'communityID', :'groupCategoryID', 'Test Group 6', 'pqr2jkl',
        'Toronto', 'CA', 'Canada', '2024-01-06 09:00:00+00',
        'Sixth group', 'https://example.com/logo6.png', :'region1ID', 'ON'),
    (:'group7ID', :'communityID', :'groupCategoryID', 'Test Group 7', 'stu3mno',
        'Madrid', 'ES', 'Spain', '2024-01-07 09:00:00+00',
        'Seventh group', 'https://example.com/logo7.png', :'region2ID', null),
    (:'group8ID', :'communityID', :'groupCategoryID', 'Test Group 8', 'vwx4pqr',
        'Boston', 'US', 'United States', '2024-01-08 09:00:00+00',
        'Eighth group', 'https://example.com/logo8.png', :'region1ID', 'MA'),
    (:'group9ID', :'communityID', :'groupCategoryID', 'Test Group 9', 'yza5stu',
        'Rome', 'IT', 'Italy', '2024-01-09 09:00:00+00',
        'Ninth group', 'https://example.com/logo9.png', :'region2ID', null),
    (:'group10ID', :'communityID', :'groupCategoryID', 'Test Group 10', 'bcd6vwx',
        'Paris', 'FR', 'France', '2024-01-10 09:00:00+00',
        'Tenth group', 'https://example.com/logo10.png', :'region2ID', null);

-- Inactive group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    city,
    country_code,
    country_name,
    created_at,
    description,
    logo_url,
    region_id,
    state
)
values (
    :'groupInactiveID',
    :'communityID',
    :'groupCategoryID',
    'Inactive Group',
    'inactive1',
    false,
    'Seattle',
    'US',
    'United States',
    '2024-01-11 09:00:00+00',
    'Inactive group',
    'https://example.com/logo-inactive.png',
    :'region1ID',
    'WA'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return groups ordered by creation date DESC
select is(
    get_community_recently_added_groups(:'communityID'::uuid)::jsonb,
    jsonb_build_array(
        get_group_summary(:'communityID'::uuid, :'group10ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group9ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group8ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group7ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group6ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group5ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group4ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group3ID'::uuid)::jsonb
    ),
    'Should return groups ordered by creation date DESC'
);

-- Should return at most eight groups
select is(
    jsonb_array_length(get_community_recently_added_groups(:'communityID'::uuid)::jsonb),
    8,
    'Should return at most eight groups'
);

-- Should not include inactive groups
select ok(
    not exists (
        select 1
        from jsonb_array_elements(get_community_recently_added_groups(:'communityID'::uuid)::jsonb) as g
        where g->>'group_id' = :'groupInactiveID'
    ),
    'Should not include inactive groups'
);

-- Should return empty array for non-existing community
select is(
    get_community_recently_added_groups(:'unknownCommunityID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty array for non-existing community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
