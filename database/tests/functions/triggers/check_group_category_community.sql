-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000010'
\set category2ID '00000000-0000-0000-0000-000000000011'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set groupID '00000000-0000-0000-0000-000000000051'

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

-- Group Category 1 (belongs to community 1)
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Group Category 2 (belongs to community 2)
insert into group_category (group_category_id, name, community_id)
values (:'category2ID', 'Business', :'community2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when group category is from same community as group
select lives_ok(
    format('insert into "group" (group_id, community_id, name, slug, description, group_category_id) values (%L, %L, %L, %L, %L, %L)',
        :'groupID', :'community1ID', 'Test Group', 'test-group', 'A test group', :'category1ID'),
    'Should succeed when group category is from same community as group'
);

-- Should fail when group category is from different community
select throws_ok(
    format('insert into "group" (group_id, community_id, name, slug, description, group_category_id) values (%L, %L, %L, %L, %L, %L)',
        gen_random_uuid(), :'community1ID', 'Another Group', 'another-group', 'Another test group', :'category2ID'),
    format('group category %s not found in community', :'category2ID'),
    'Should fail when group category is from different community'
);

-- Should fail when updating group to category from different community
select throws_ok(
    format('update "group" set group_category_id = %L where group_id = %L', :'category2ID', :'groupID'),
    format('group category %s not found in community', :'category2ID'),
    'Should fail when updating group to category from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
