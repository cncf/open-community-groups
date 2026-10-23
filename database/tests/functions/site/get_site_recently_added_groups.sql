-- Tests listing the groups recently added to the site.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

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
\set groupInactiveID '9a030000-0000-0000-0000-000000000016'
\set groupTieFirstID '9a030000-0000-0000-0000-000000000017'
\set groupTieSecondID '9a030000-0000-0000-0000-000000000018'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community owning the listed groups
select fx_community(:'communityID');

-- Inactive community whose groups are excluded
select fx_community(:'community2ID', jsonb_build_object('active', false));

-- Group category in the active community
select fx_group_category(:'groupCategory1ID', :'communityID');

-- Group category in the inactive community
select fx_group_category(:'groupCategory2ID', :'community2ID');

-- Active group created on January 1
select fx_group(:'group1ID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-01 09:00:00+00'));

-- Active group created on January 2
select fx_group(:'group2ID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-02 09:00:00+00'));

-- Active group created on January 3
select fx_group(:'group3ID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-03 09:00:00+00'));

-- Active group created on January 4
select fx_group(:'group4ID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-04 09:00:00+00'));

-- Active group created on January 6
select fx_group(:'group6ID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-06 09:00:00+00'));

-- Active group created on January 7
select fx_group(:'group7ID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-07 09:00:00+00'));

-- Active group created on January 8
select fx_group(:'group8ID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-08 09:00:00+00'));

-- Active group created on January 9
select fx_group(:'group9ID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-09 09:00:00+00'));

-- Active group created on January 10
select fx_group(:'group10ID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-10 09:00:00+00'));

-- Active group created on January 11
select fx_group(:'group11ID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-11 09:00:00+00'));

-- Active group sharing the newest active creation time with the lower group id
select fx_group(:'groupTieFirstID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-12 09:00:00+00'));

-- Active group sharing the newest active creation time with the higher group id
select fx_group(:'groupTieSecondID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', true, 'created_at', '2024-01-12 09:00:00+00'));

-- Newer active group in the inactive community
select fx_group(:'group5ID', :'community2ID', :'groupCategory2ID', jsonb_build_object('active', true, 'created_at', '2024-01-13 09:00:00+00'));

-- Newest inactive group in the active community
select fx_group(:'groupInactiveID', :'communityID', :'groupCategory1ID', jsonb_build_object('active', false, 'created_at', '2024-01-14 09:00:00+00'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not include groups from inactive communities
select ok(
    not exists (
        select 1
        from jsonb_array_elements(get_site_recently_added_groups()::jsonb) as g
        where g->>'group_id' = :'group5ID'
    ),
    'Should not include groups from inactive communities'
);

-- Should not include inactive groups
select ok(
    not exists (
        select 1
        from jsonb_array_elements(get_site_recently_added_groups()::jsonb) as g
        where g->>'group_id' = :'groupInactiveID'
    ),
    'Should not include inactive groups'
);

-- Should order groups with the same creation time by group id
select is(
    (
        select jsonb_agg(g->>'group_id' order by position)
        from jsonb_array_elements(get_site_recently_added_groups()::jsonb) with ordinality as items(g, position)
        where position <= 2
    ),
    jsonb_build_array(:'groupTieFirstID', :'groupTieSecondID'),
    'Should order groups with the same creation time by group id'
);

-- Should return at most eight groups
select is(
    jsonb_array_length(get_site_recently_added_groups()::jsonb),
    8,
    'Should return at most eight groups'
);

-- Should return groups ordered by creation date DESC
select is(
    get_site_recently_added_groups()::jsonb,
    jsonb_build_array(
        get_group_summary(:'communityID'::uuid, :'groupTieFirstID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'groupTieSecondID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group11ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group10ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group9ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group8ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group7ID'::uuid)::jsonb,
        get_group_summary(:'communityID'::uuid, :'group6ID'::uuid)::jsonb
    ),
    'Should return groups ordered by creation date DESC'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
