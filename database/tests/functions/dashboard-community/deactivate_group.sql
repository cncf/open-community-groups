-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupID '00000000-0000-0000-0000-000000000021'
\set groupAlreadyDeletedID '00000000-0000-0000-0000-000000000022'
\set groupAlreadyInactiveID '00000000-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

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
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'seattle.cloudnative.org',
    'Cloud Native Seattle Community',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    created_at
) values (
    :'groupID',
    'Kubernetes Study Group',
    'kubernetes-study-group',
    :'communityID',
    :'categoryID',
    'A study group focused on Kubernetes best practices and implementation',
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
    'Docker Meetup',
    'docker-meetup-deleted',
    :'communityID',
    :'categoryID',
    'A Docker-focused meetup group that was previously deleted',
    false,
    true,
    '2024-02-15 10:00:00+00',
    '2024-01-15 10:00:00+00'
);

-- Group (inactive)
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    active,
    deleted,
    created_at
) values (
    :'groupAlreadyInactiveID',
    'Prometheus Workshop',
    'prometheus-workshop',
    :'communityID',
    :'categoryID',
    'A workshop series for learning Prometheus monitoring',
    false,
    false,
    '2024-01-20 10:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: deactivate_group should set active to false
select deactivate_group(:'communityID'::uuid, :'groupID'::uuid);

-- Test: deactivate_group should set active to false
select is(
    (select active from "group" where group_id = :'groupID'::uuid),
    false,
    'deactivate_group should set active to false'
);

-- Test: deactivate_group should not set deleted flag
select is(
    (select deleted from "group" where group_id = :'groupID'::uuid),
    false,
    'deactivate_group should not set deleted flag'
);

-- Test: deactivate_group already inactive should succeed (idempotent)
select lives_ok(
    $$select deactivate_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000023'::uuid)$$,
    'deactivate_group should be idempotent for already inactive groups'
);

-- Test: deactivate_group should throw error for already deleted group
select throws_ok(
    $$select deactivate_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000022'::uuid)$$,
    'P0001',
    'group not found',
    'deactivate_group should throw error when trying to deactivate already deleted group'
);

-- Test: deactivate_group should throw error for wrong community_id
select throws_ok(
    $$select deactivate_group('00000000-0000-0000-0000-000000000099'::uuid, '00000000-0000-0000-0000-000000000021'::uuid)$$,
    'P0001',
    'group not found',
    'deactivate_group should throw error when community_id does not match'
);

-- Test: deactivate_group should throw error for non-existent group
select throws_ok(
    $$select deactivate_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000099'::uuid)$$,
    'P0001',
    'group not found',
    'deactivate_group should throw error for non-existent group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
