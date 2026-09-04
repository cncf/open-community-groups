-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c0a0000-0000-0000-0000-000000000001'
\set childGroupID '2c0a0000-0000-0000-0000-000000000007'
\set groupAlreadyDeletedID '2c0a0000-0000-0000-0000-000000000002'
\set groupCategoryID '2c0a0000-0000-0000-0000-000000000003'
\set groupID '2c0a0000-0000-0000-0000-000000000004'
\set groupWrongCommunityID '2c0a0000-0000-0000-0000-000000000005'
\set linkedGroupID '2c0a0000-0000-0000-0000-000000000008'
\set unknownCommunityID '2c0a0000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group category and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupWrongCommunityID', :'communityID', :'groupCategoryID');

select fx_group(:'childGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'groupID'));

-- Already deleted group
select fx_group(:'groupAlreadyDeletedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Group with its own parent link
select fx_group(:'linkedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'groupWrongCommunityID'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should perform soft delete
select lives_ok(
    format(
        'select delete_group(null::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'groupID'
    ),
    'Should perform soft delete'
);

select is(
    (select deleted from "group" where group_id = :'groupID'::uuid),
    true,
    'Should set deleted to true'
);

select ok(
    (select deleted_at from "group" where group_id = :'groupID'::uuid) is not null,
    'Should set deleted_at timestamp'
);

-- Should perform soft delete (record still exists)
select ok(
    exists(select 1 from "group" where group_id = :'groupID'::uuid),
    'Should perform soft delete (record still exists)'
);

-- Should set active to false when deleting
select is(
    (select active from "group" where group_id = :'groupID'::uuid),
    false,
    'Should set active to false when deleting'
);

-- Should clear child links for deleted parent group
select is(
    (select parent_group_id from "group" where group_id = :'childGroupID'::uuid),
    null::uuid,
    'Should clear child links for deleted parent group'
);

-- Should clear the deleted group's own parent link
select lives_ok(
    format(
        'select delete_group(null::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'linkedGroupID'
    ),
    'Should delete a group that has a parent link'
);

select is(
    (select parent_group_id from "group" where group_id = :'linkedGroupID'::uuid),
    null::uuid,
    'Should clear the deleted group own parent link'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values
            (
                'group_deleted',
                null::uuid,
                null::text,
                %L::uuid,
                %L::uuid,
                'group',
                %L::uuid
            ),
            (
                'group_deleted',
                null::uuid,
                null::text,
                %L::uuid,
                %L::uuid,
                'group',
                %L::uuid
            )
        $$,
        :'communityID',
        :'groupID',
        :'groupID',
        :'communityID',
        :'linkedGroupID',
        :'linkedGroupID'
    ),
    'Should create the expected audit row'
);

-- Should throw error for already deleted group
select throws_ok(
    format(
        $$select delete_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'communityID',
        :'groupAlreadyDeletedID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should throw error when trying to delete already deleted group'
);

-- Should throw error for wrong community_id
select throws_ok(
    format(
        $$select delete_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'unknownCommunityID',
        :'groupWrongCommunityID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should throw error when community_id does not match'
);

-- Should leave the group untouched when community_id does not match
select is(
    (select deleted from "group" where group_id = :'groupWrongCommunityID'::uuid),
    false,
    'Should leave the group untouched when community_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
