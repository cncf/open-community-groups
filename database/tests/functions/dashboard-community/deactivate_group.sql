-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupAlreadyDeletedID '00000000-0000-0000-0000-000000000022'
\set groupAlreadyInactiveID '00000000-0000-0000-0000-000000000023'
\set groupID '00000000-0000-0000-0000-000000000021'

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

-- Should set active to false
select deactivate_group(:'communityID'::uuid, :'groupID'::uuid);

-- Should set active to false
select is(
    (select active from "group" where group_id = :'groupID'::uuid),
    false,
    'Should set active to false'
);

-- Should not set deleted flag
select is(
    (select deleted from "group" where group_id = :'groupID'::uuid),
    false,
    'Should not set deleted flag'
);

-- Should be idempotent for already inactive groups
select lives_ok(
    $$select deactivate_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000023'::uuid)$$,
    'Should be idempotent for already inactive groups'
);

-- Should throw error for already deleted group
select throws_ok(
    $$select deactivate_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000022'::uuid)$$,
    'group not found or inactive',
    'Should throw error when trying to deactivate already deleted group'
);

-- Should throw error for wrong community_id
select throws_ok(
    $$select deactivate_group('00000000-0000-0000-0000-000000000099'::uuid, '00000000-0000-0000-0000-000000000021'::uuid)$$,
    'group not found or inactive',
    'Should throw error when community_id does not match'
);

-- Should throw error for non-existent group
select throws_ok(
    $$select deactivate_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000099'::uuid)$$,
    'group not found or inactive',
    'Should throw error for non-existent group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
