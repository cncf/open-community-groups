-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c020000-0000-0000-0000-000000000001'
\set user1ID '2c020000-0000-0000-0000-000000000002'
\set user2ID '2c020000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and users
select fx_community(:'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Adding a user should create membership
select lives_ok(
    format(
        $$ select add_community_team_member(null::uuid, %L::uuid, %L::uuid, 'admin') $$,
        :'communityID',
        :'user1ID'
    ),
    'Should succeed for valid user'
);
select results_eq(
    format(
        $$
    select
        count(*)::bigint,
        bool_or(accepted)
    from community_team
    where community_id = %L::uuid
      and user_id = %L::uuid
        $$,
        :'communityID',
        :'user1ID'
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
            resource_type,
            resource_id,
            details
        from audit_log
    $$,
    format(
        $$
        values (
            'community_team_member_added',
            null::uuid,
            null::text,
            %L::uuid,
            'user',
            %L::uuid,
            jsonb_build_object('role', 'admin')
        )
        $$,
        :'communityID',
        :'user1ID'
    ),
    'Should create the expected audit row'
);

-- Should not allow duplicate community team membership
select throws_ok(
    format(
        $$ select add_community_team_member(null::uuid, %L::uuid, %L::uuid, 'admin') $$,
        :'communityID',
        :'user1ID'
    ),
    'OCG01',
    'user is already a community team member',
    'Should not allow duplicate community team membership'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
