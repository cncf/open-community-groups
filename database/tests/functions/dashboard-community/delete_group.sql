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

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Active group
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

-- Already deleted group
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

-- ============================================================================
-- TESTS
-- ============================================================================

-- delete_group function performs soft delete
select delete_group(:'communityID'::uuid, :'groupID'::uuid);

select is(
    (select deleted from "group" where group_id = :'groupID'::uuid),
    true,
    'delete_group should set deleted to true'
);

select ok(
    (select deleted_at from "group" where group_id = :'groupID'::uuid) is not null,
    'delete_group should set deleted_at timestamp'
);

-- Verify the group still exists in database
select ok(
    exists(select 1 from "group" where group_id = :'groupID'::uuid),
    'delete_group should perform soft delete (record still exists)'
);

-- Verify active field is set to false when deleting
select is(
    (select active from "group" where group_id = :'groupID'::uuid),
    false,
    'delete_group should set active to false when deleting'
);

-- delete_group throws error for already deleted group
select throws_ok(
    $$select delete_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000022'::uuid)$$,
    'P0001',
    'group not found or inactive',
    'delete_group should throw error when trying to delete already deleted group'
);

-- delete_group throws error for wrong community_id
select throws_ok(
    $$select delete_group('00000000-0000-0000-0000-000000000099'::uuid, '00000000-0000-0000-0000-000000000021'::uuid)$$,
    'P0001',
    'group not found or inactive',
    'delete_group should throw error when community_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
