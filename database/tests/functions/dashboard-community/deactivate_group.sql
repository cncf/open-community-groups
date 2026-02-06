-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

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
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'Community 1', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug
) values (
    :'groupID',
    :'communityID',
    :'categoryID',
    'G1',
    'g1'
);

-- Group (deleted)
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values (
    :'groupAlreadyDeletedID',
    :'communityID',
    :'categoryID',
    'G2',
    'g2',
    false,
    true
);

-- Group (inactive)
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values (
    :'groupAlreadyInactiveID',
    :'communityID',
    :'categoryID',
    'G3',
    'g3',
    false,
    false
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set active to false
select lives_ok(
    format(
        'select deactivate_group(%L::uuid, %L::uuid)',
        :'communityID',
        :'groupID'
    ),
    'Should execute deactivate_group successfully'
);

-- Should set active to false
select is(
    (select active from "group" where group_id = :'groupID'::uuid),
    false,
    'Should set active flag to false'
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
