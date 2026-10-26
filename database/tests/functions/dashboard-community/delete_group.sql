-- Tests soft-deleting dashboard community groups.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '2c0a0000-0000-0000-0000-000000000002'
\set childGroupID '2c0a0000-0000-0000-0000-000000000007'
\set communityID '2c0a0000-0000-0000-0000-000000000001'
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

-- Actor recorded in the audit row
select fx_user(:'actorUserID', jsonb_build_object('username', 'delete-group-audit-actor'));

-- Child group linked to the deleted parent group
select fx_group(:'childGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'groupID'));

-- Group with its own parent link
select fx_group(:'linkedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'groupWrongCommunityID'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should perform soft delete
select lives_ok(
    format(
        'select delete_group(%L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'communityID',
        :'groupID'
    ),
    'Should perform soft delete'
);
select is(
    (
        select jsonb_build_object(
            'active', active,
            'deleted', deleted,
            'deleted_at', deleted_at
        )
        from "group"
        where group_id = :'groupID'::uuid
    ),
    jsonb_build_object(
        'active', false,
        'deleted', true,
        'deleted_at', current_timestamp
    ),
    'Should deactivate the group and set the deletion fields'
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
        order by resource_id
    $$,
    format(
        $$
        values
            (
                'group_deleted',
                %L::uuid,
                'delete-group-audit-actor',
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
        :'actorUserID',
        :'communityID',
        :'groupID',
        :'groupID',
        :'communityID',
        :'linkedGroupID',
        :'linkedGroupID'
    ),
    'Should create the expected audit row'
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
