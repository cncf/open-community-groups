-- Tests deactivating dashboard community groups.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c070000-0000-0000-0000-000000000001'
\set groupAlreadyInactiveID '2c070000-0000-0000-0000-000000000003'
\set groupCategoryID '2c070000-0000-0000-0000-000000000004'
\set groupID '2c070000-0000-0000-0000-000000000005'
\set unknownGroupID '2c070000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group category and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group (inactive)
select fx_group(:'groupAlreadyInactiveID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set active to false
select lives_ok(
    format(
        'select deactivate_group(null::uuid, %L::uuid, %L::uuid)',
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
            'group_deactivated',
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

-- Should be idempotent for already inactive groups
select lives_ok(
    format(
        $$select deactivate_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'communityID',
        :'groupAlreadyInactiveID'
    ),
    'Should be idempotent for already inactive groups'
);

-- Should throw error for non-existent group
select throws_ok(
    format(
        $$select deactivate_group(null::uuid, %L::uuid, %L::uuid)$$,
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
