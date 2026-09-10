-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c150000-0000-0000-0000-000000000001'
\set unknownUserID '2c150000-0000-0000-0000-000000000002'
\set user1ID '2c150000-0000-0000-0000-000000000003'
\set user2ID '2c150000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and users
select fx_community(:'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');

insert into community_team (community_id, user_id, role, accepted)
values
    (:'communityID', :'user1ID', 'viewer', true),
    (:'communityID', :'user2ID', 'admin', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should change existing member role
select lives_ok(
    format(
        $$ select update_community_team_member_role(null::uuid, %L::uuid, %L::uuid, 'admin') $$,
        :'communityID',
        :'user1ID'
    ),
    'Should update member role to admin'
);
select results_eq(
    format(
        $$ select role from community_team where community_id = %L::uuid and user_id = %L::uuid $$,
        :'communityID',
        :'user1ID'
    ),
    $$ values ('admin'::text) $$,
    'Role should be updated to admin'
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
            'community_team_member_role_updated',
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

-- Should error when updating role for non-existing member
select throws_ok(
    format(
        $$ select update_community_team_member_role(null::uuid, %L::uuid, %L::uuid, 'admin') $$,
        :'communityID',
        :'unknownUserID'
    ),
    'OCG01',
    'user is not a community team member',
    'Should error when updating role for non-existing member'
);

-- Should error when updating role to an invalid value
select throws_ok(
    format(
        $$ select update_community_team_member_role(null::uuid, %L::uuid, %L::uuid, 'invalid') $$,
        :'communityID',
        :'user1ID'
    ),
    '23503',
    null,
    'Should error when updating role to an invalid value'
);

-- Should allow demoting an admin when another accepted admin remains
select lives_ok(
    format(
        $$ select update_community_team_member_role(null::uuid, %L::uuid, %L::uuid, 'viewer') $$,
        :'communityID',
        :'user1ID'
    ),
    'Should allow demotion when another accepted admin exists'
);

-- Should block demoting the last accepted community admin
select throws_ok(
    format(
        $$ select update_community_team_member_role(null::uuid, %L::uuid, %L::uuid, 'viewer') $$,
        :'communityID',
        :'user2ID'
    ),
    'OCG01',
    'cannot change role for the last accepted community admin',
    'Should block demoting the last accepted community admin'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
