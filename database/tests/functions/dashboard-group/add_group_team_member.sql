-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a050000-0000-0000-0000-000000000001'
\set groupCategoryID '3a050000-0000-0000-0000-000000000002'
\set groupID '3a050000-0000-0000-0000-000000000003'
\set user1ID '3a050000-0000-0000-0000-000000000004'
\set user2ID '3a050000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create pending membership
select lives_ok(
    format(
        $$select add_group_team_member(null::uuid, %L::uuid, %L::uuid, 'admin')$$,
        :'groupID', :'user1ID'
    ),
    'Should succeed for valid user'
);
select results_eq(
    format(
        $$
        select count(*)::bigint, bool_or(accepted)
        from group_team
        where group_id = %L::uuid
          and user_id = %L::uuid
        $$,
        :'groupID', :'user1ID'
    ),
    $$ values (1::bigint, false) $$,
    'Membership should be created with accepted = false'
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
            resource_id,
            details
        from audit_log
    $$,
    format(
        $$
        values (
            'group_team_member_added',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            'user',
            %L::uuid,
            jsonb_build_object('role', 'admin')
        )
        $$,
        :'communityID', :'groupID', :'user1ID'
    ),
    'Should create the expected audit row'
);

-- Should not allow adding membership with invalid role
select throws_ok(
    format(
        $$select add_group_team_member(null::uuid, %L::uuid, %L::uuid, 'invalid')$$,
        :'groupID', :'user2ID'
    ),
    '23503',
    null,
    'Should not allow adding membership with invalid role'
);

-- Should not allow duplicate group team membership
select throws_ok(
    format(
        $$select add_group_team_member(null::uuid, %L::uuid, %L::uuid, 'admin')$$,
        :'groupID', :'user1ID'
    ),
    'OCG01',
    'user is already a group team member',
    'Should not allow duplicate group team membership'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
