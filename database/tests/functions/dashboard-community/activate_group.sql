-- =============================================================================
-- SETUP
-- =============================================================================

begin;
select plan(4);

-- =============================================================================
-- VARIABLES
-- =============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupID '00000000-0000-0000-0000-000000000031'
\set groupAlreadyDeletedID '00000000-0000-0000-0000-000000000032'

-- =============================================================================
-- SEED DATA
-- =============================================================================

-- Community
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
    :'communityID',
    'cloud-native-nyc',
    'Cloud Native NYC',
    'nyc.cloudnative.org',
    'Cloud Native NYC Community',
    'A community for cloud native technologies and practices in NYC',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Group (inactive)
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    active,
    created_at
) values (
    :'groupID',
    'Service Mesh Study Group',
    'service-mesh-study-group',
    :'communityID',
    :'categoryID',
    'A study group focused on service meshes',
    false,
    '2024-01-15 10:00:00+00'
);

-- Group (deleted)
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    active,
    deleted,
    deleted_at,
    created_at
) values (
    :'groupAlreadyDeletedID',
    'CNF Meetup',
    'cnf-meetup-deleted',
    :'communityID',
    :'categoryID',
    'A deleted meetup group',
    false,
    true,
    '2024-02-15 10:00:00+00',
    '2024-01-15 10:00:00+00'
);


-- =============================================================================
-- TESTS
-- =============================================================================

-- Test: activate_group should set active to true
select activate_group(:'communityID'::uuid, :'groupID'::uuid);

-- Test: activate_group should set active to true
select is(
    (select active from "group" where group_id = :'groupID'::uuid),
    true,
    'activate_group should set active to true'
);

-- Test: activate_group should throw error for already deleted group
select throws_ok(
    $$select activate_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000032'::uuid)$$,
    'P0001',
    'group not found',
    'activate_group should throw error when trying to activate already deleted group'
);

-- Test: activate_group should throw error for wrong community_id
select throws_ok(
    $$select activate_group('00000000-0000-0000-0000-000000000099'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'P0001',
    'group not found',
    'activate_group should throw error when community_id does not match'
);

-- Test: activate_group should throw error for non-existent group
select throws_ok(
    $$select activate_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000099'::uuid)$$,
    'P0001',
    'group not found',
    'activate_group should throw error for non-existent group'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

select * from finish();
rollback;
