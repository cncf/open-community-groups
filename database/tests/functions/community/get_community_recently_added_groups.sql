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

-- Baseline community and category for recently added groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Region
insert into region (region_id, name, community_id)
values
    (:'region1ID', 'North America', :'communityID'),
    (:'region2ID', 'Europe', :'communityID');

-- Groups ordered by creation date
select fx_group(:'group1ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', '2024-01-01 09:00:00+00'));
select fx_group(:'group2ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', '2024-01-02 09:00:00+00'));
select fx_group(:'group3ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', '2024-01-03 09:00:00+00'));
select fx_group(:'group4ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', '2024-01-04 09:00:00+00'));
select fx_group(:'group5ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', '2024-01-05 09:00:00+00'));
select fx_group(:'group6ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', '2024-01-06 09:00:00+00'));
select fx_group(:'group7ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', '2024-01-07 09:00:00+00'));
select fx_group(:'group8ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', '2024-01-08 09:00:00+00'));
select fx_group(:'group9ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', '2024-01-09 09:00:00+00'));
select fx_group(:'group10ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', '2024-01-10 09:00:00+00'));

-- Inactive group excluded from recent results
select fx_group(:'groupInactiveID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'created_at', '2024-01-11 09:00:00+00'
));

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
