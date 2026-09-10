-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '9a030000-0000-0000-0000-000000000001'
\set communityID '9a030000-0000-0000-0000-000000000002'
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

-- Baseline active community and category for recently added groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategory1ID', :'communityID');

-- Inactive community whose groups are excluded
select fx_community(:'community2ID', jsonb_build_object('active', false));
select fx_group_category(:'groupCategory2ID', :'community2ID');

-- Region
insert into region (region_id, name, community_id)
values
    (:'region1ID', 'North America', :'communityID'),
    (:'region2ID', 'Europe', :'communityID');

-- Groups ordered by creation date across site results
select fx_group(:'group1ID', :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-01 09:00:00+00'));
select fx_group(:'group2ID', :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-02 09:00:00+00'));
select fx_group(:'group3ID', :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-03 09:00:00+00'));
select fx_group(:'group4ID', :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-04 09:00:00+00'));
select fx_group(:'group5ID', :'community2ID', :'groupCategory2ID', jsonb_build_object('created_at', '2024-01-05 09:00:00+00'));
select fx_group(:'group6ID', :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-06 09:00:00+00'));
select fx_group(:'group7ID', :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-07 09:00:00+00'));
select fx_group(:'group8ID', :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-08 09:00:00+00'));
select fx_group(:'group9ID', :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-09 09:00:00+00'));
select fx_group(:'group10ID', :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-10 09:00:00+00'));
select fx_group(:'group11ID', :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-11 09:00:00+00'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return groups ordered by creation date DESC
select is(
    get_site_recently_added_groups()::jsonb,
    jsonb_build_array(
        get_group_summary(:'communityID'::uuid, :'group11ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group10ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group9ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group8ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group7ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group6ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group4ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group3ID'::uuid)::jsonb
    ),
    'Should return groups ordered by creation date DESC'
);

-- Should return at most eight groups
select is(
    jsonb_array_length(get_site_recently_added_groups()::jsonb),
    8,
    'Should return at most eight groups'
);

-- Should not include groups from inactive communities
select ok(
    not exists (
        select 1
        from jsonb_array_elements(get_site_recently_added_groups()::jsonb) as g
        where g->>'group_id' = :'group5ID'
    ),
    'Should not include groups from inactive communities'
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
