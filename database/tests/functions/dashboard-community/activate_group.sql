-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupAlreadyDeletedID '00000000-0000-0000-0000-000000000032'
\set groupID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'Community 1', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Group (inactive)
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active
) values (
    :'groupID',
    :'communityID',
    :'categoryID',
    'G1',
    'g1',
    false
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


-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set active to true
select lives_ok(
    format(
        'select activate_group(%L::uuid, %L::uuid)',
        :'communityID',
        :'groupID'
    ),
    'Should execute activate_group successfully'
);

-- Should set active to true
select is(
    (select active from "group" where group_id = :'groupID'::uuid),
    true,
    'Should set active flag to true'
);

-- Should throw error for already deleted group
select throws_ok(
    $$select activate_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000032'::uuid)$$,
    'group not found or inactive',
    'Should throw error when trying to activate already deleted group'
);

-- Should throw error for wrong community_id
select throws_ok(
    $$select activate_group('00000000-0000-0000-0000-000000000099'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'group not found or inactive',
    'Should throw error when community_id does not match'
);

-- Should throw error for non-existent group
select throws_ok(
    $$select activate_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000099'::uuid)$$,
    'group not found or inactive',
    'Should throw error for non-existent group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
