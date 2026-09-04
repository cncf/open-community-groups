-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c010000-0000-0000-0000-000000000001'
\set groupAlreadyDeletedID '2c010000-0000-0000-0000-000000000002'
\set groupCategoryID '2c010000-0000-0000-0000-000000000003'
\set groupID '2c010000-0000-0000-0000-000000000004'
\set unknownCommunityID '2c010000-0000-0000-0000-000000000005'
\set unknownGroupID '2c010000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and group category
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Group (deleted)
select fx_group(:'groupAlreadyDeletedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));


-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set active to true
select lives_ok(
    format(
        'select activate_group(null::uuid, %L::uuid, %L::uuid)',
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
        values (
            'group_activated',
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
        :'groupID'
    ),
    'Should create the expected audit row'
);

-- Should throw error for already deleted group
select throws_ok(
    format(
        $$select activate_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'communityID',
        :'groupAlreadyDeletedID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should throw error when trying to activate already deleted group'
);

-- Should throw error for wrong community_id
select throws_ok(
    format(
        $$select activate_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'unknownCommunityID',
        :'groupID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should throw error when community_id does not match'
);

-- Should throw error for non-existent group
select throws_ok(
    format(
        $$select activate_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'communityID',
        :'unknownGroupID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should throw error for non-existent group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
