-- Tests deleting dashboard community group categories.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '2c0b0000-0000-0000-0000-000000000007'
\set communityID '2c0b0000-0000-0000-0000-000000000001'
\set foreignGroupCategoryID '2c0b0000-0000-0000-0000-000000000004'
\set groupID '2c0b0000-0000-0000-0000-000000000002'
\set inUseGroupCategoryID '2c0b0000-0000-0000-0000-000000000003'
\set otherCommunityID '2c0b0000-0000-0000-0000-000000000006'
\set unusedGroupCategoryID '2c0b0000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group category and groups
select fx_community(:'communityID');
select fx_group_category(:'inUseGroupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'inUseGroupCategoryID');

-- Unused group category deleted by the success scenario
select fx_group_category(:'unusedGroupCategoryID', :'communityID', jsonb_build_object('name', 'Security'));

-- Other community with its own group category
select fx_community(:'otherCommunityID');
select fx_group_category(:'foreignGroupCategoryID', :'otherCommunityID');

-- Actor recorded in the audit row
select fx_user(:'actorUserID', jsonb_build_object('username', 'delete-group-category-audit-actor'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block deleting category that is still referenced by groups
select throws_ok(
    format(
        $$ select delete_group_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'inUseGroupCategoryID'
    ),
    'OCG01',
    'cannot delete group category in use by groups',
    'Should block deleting group category referenced by groups'
);

-- Should delete category with no group references
select lives_ok(
    format(
        $$ select delete_group_category(
        %L::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'actorUserID',
        :'communityID',
        :'unusedGroupCategoryID'
    ),
    'Should delete an unused group category'
);
select results_eq(
    format(
        $$
    select count(*)::bigint
    from group_category gc
    where gc.group_category_id = %L::uuid
        $$,
        :'unusedGroupCategoryID'
    ),
    $$ values (0::bigint) $$,
    'Unused group category should be deleted'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            details,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'group_category_deleted',
            %L::uuid,
            'delete-group-category-audit-actor',
            %L::uuid,
            '{"name": "Security"}'::jsonb,
            'group_category',
            %L::uuid
        )
        $$,
        :'actorUserID',
        :'communityID',
        :'unusedGroupCategoryID'
    ),
    'Should create the expected audit row'
);

-- Should fail when target category belongs to another community
select throws_ok(
    format(
        $$ select delete_group_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'foreignGroupCategoryID'
    ),
    'OCG01',
    'group category not found',
    'Should fail when deleting a group category from another community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
