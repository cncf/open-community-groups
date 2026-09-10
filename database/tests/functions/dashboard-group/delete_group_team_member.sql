-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a0d0000-0000-0000-0000-000000000001'
\set groupCategoryID '3a0d0000-0000-0000-0000-000000000002'
\set groupID '3a0d0000-0000-0000-0000-000000000003'
\set user1ID '3a0d0000-0000-0000-0000-000000000004'
\set user2ID '3a0d0000-0000-0000-0000-000000000005'
\set user3ID '3a0d0000-0000-0000-0000-000000000006'
\set user4ID '3a0d0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');


-- Group team membership
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupID', :'user1ID', 'admin', true),
    (:'groupID', :'user2ID', 'admin', true),
    (:'groupID', :'user3ID', 'admin', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow deleting an accepted member when another accepted member remains
select lives_ok(
    format(
        $$ select delete_group_team_member(null::uuid, %L::uuid, %L::uuid) $$,
        :'groupID', :'user2ID'
    ),
    'Should allow deleting an accepted member when another accepted member exists'
);
select results_eq(
    format(
        $$
            select count(*)
            from group_team
            where group_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'groupID', :'user2ID'
    ),
    $$ values (0::bigint) $$,
    'Deleted accepted membership should be removed'
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
            'group_team_member_removed',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            'user',
            %L::uuid
        )
        $$,
        :'communityID', :'groupID', :'user2ID'
    ),
    'Should create the expected audit row'
);

-- Should allow deleting a pending invitation when there is one accepted member left
select lives_ok(
    format(
        $$ select delete_group_team_member(null::uuid, %L::uuid, %L::uuid) $$,
        :'groupID', :'user3ID'
    ),
    'Should allow deleting a pending invitation with only one accepted member left'
);

-- Should block deleting the last accepted member
select throws_ok(
    format(
        $$ select delete_group_team_member(null::uuid, %L::uuid, %L::uuid) $$,
        :'groupID', :'user1ID'
    ),
    'OCG01',
    'cannot remove the last accepted group admin',
    'Should block deleting the last accepted member'
);
select results_eq(
    format(
        $$
            select count(*)
            from group_team
            where group_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'groupID', :'user1ID'
    ),
    $$ values (1::bigint) $$,
    'Last accepted membership should remain after blocked delete'
);

-- Should raise error when deleting non-existing member
select throws_ok(
    format(
        $$ select delete_group_team_member(null::uuid, %L::uuid, %L::uuid) $$,
        :'groupID', :'user4ID'
    ),
    'OCG01',
    'user is not a group team member',
    'Should raise error when deleting non-existing member'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
