-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000010'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set groupID '00000000-0000-0000-0000-000000000051'
\set region1ID '00000000-0000-0000-0000-000000000030'
\set region2ID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community 1
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
    'community-1',
    'Community 1',
    'community1.example.org',
    'Community 1',
    'Test community 1',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Community 2
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
    :'community2ID',
    'community-2',
    'Community 2',
    'community2.example.org',
    'Community 2',
    'Test community 2',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category (belongs to community 1)
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'community1ID');

-- Region 1 (belongs to community 1)
insert into region (region_id, name, community_id)
values (:'region1ID', 'North America', :'community1ID');

-- Region 2 (belongs to community 2)
insert into region (region_id, name, community_id)
values (:'region2ID', 'Europe', :'community2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when group has no region (null)
select lives_ok(
    format('insert into "group" (group_id, community_id, name, slug, description, group_category_id, region_id) values (%L, %L, %L, %L, %L, %L, NULL)',
        :'groupID', :'community1ID', 'Test Group', 'test-group', 'A test group', :'categoryID'),
    'Should succeed when group has no region (null)'
);

-- Should succeed when region is from same community as group
select lives_ok(
    format('update "group" set region_id = %L where group_id = %L', :'region1ID', :'groupID'),
    'Should succeed when region is from same community as group'
);

-- Should fail when region is from different community
select throws_ok(
    format('update "group" set region_id = %L where group_id = %L', :'region2ID', :'groupID'),
    format('region %s not found in community', :'region2ID'),
    'Should fail when region is from different community'
);

-- Should fail when inserting group with region from different community
select throws_ok(
    format('insert into "group" (group_id, community_id, name, slug, description, group_category_id, region_id) values (%L, %L, %L, %L, %L, %L, %L)',
        gen_random_uuid(), :'community1ID', 'Another Group', 'another-group', 'Another test group', :'categoryID', :'region2ID'),
    format('region %s not found in community', :'region2ID'),
    'Should fail when inserting group with region from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
