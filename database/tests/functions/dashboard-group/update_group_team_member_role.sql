-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a3f0000-0000-0000-0000-000000000001'
\set groupCategoryID '3a3f0000-0000-0000-0000-000000000002'
\set groupID '3a3f0000-0000-0000-0000-000000000003'
\set missingUserID '3a3f0000-0000-0000-0000-000000000004'
\set pendingGroupID '3a3f0000-0000-0000-0000-000000000005'
\set user1ID '3a3f0000-0000-0000-0000-000000000006'
\set user2ID '3a3f0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'test-alliance',
    'Test Alliance',
    'A test alliance',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values
    (:'groupID', :'allianceID', :'groupCategoryID', 'Test Group', 'test-group'),
    (:'pendingGroupID', :'allianceID', :'groupCategoryID', 'Pending Group', 'pending-group');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified)
values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'alice', true),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'bob', true);

-- Group team membership
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupID', :'user1ID', 'admin', true),
    (:'groupID', :'user2ID', 'admin', true);

-- Group team membership with a pending admin
insert into group_team (group_id, user_id, role, accepted)
values
    (:'pendingGroupID', :'user1ID', 'admin', true),
    (:'pendingGroupID', :'user2ID', 'admin', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should change existing member role
select lives_ok(
    format(
        $$select update_group_team_member_role(null::uuid, %L::uuid, %L::uuid, 'admin')$$,
        :'groupID', :'user1ID'
    ),
    'Should change existing member role'
);
select results_eq(
    format(
        $$select role from group_team where group_id = %L::uuid and user_id = %L::uuid$$,
        :'groupID', :'user1ID'
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
            alliance_id,
            group_id,
            resource_type,
            resource_id,
            details
        from audit_log
    $$,
    format(
        $$
        values (
            'group_team_member_role_updated',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            'user',
            %L::uuid,
            jsonb_build_object('role', 'admin')
        )
        $$,
        :'allianceID', :'groupID', :'user1ID'
    ),
    'Should create the expected audit row'
);

-- Should block demoting the last accepted group admin when another admin is pending
select throws_ok(
    format(
        $$select update_group_team_member_role(null::uuid, %L::uuid, %L::uuid, 'viewer')$$,
        :'pendingGroupID', :'user1ID'
    ),
    'cannot change role for the last accepted group admin',
    'Should block demoting the last accepted group admin when another admin is pending'
);

-- Should error when updating role for non-existing member
select throws_ok(
    format(
        $$select update_group_team_member_role(null::uuid, %L::uuid, %L::uuid, 'admin')$$,
        :'groupID', :'missingUserID'
    ),
    'user is not a group team member',
    'Should error when updating role for non-existing member'
);

-- Should error when updating role to an invalid value
select throws_ok(
    format(
        $$select update_group_team_member_role(null::uuid, %L::uuid, %L::uuid, 'invalid')$$,
        :'groupID', :'user1ID'
    ),
    '23503',
    null,
    'Should error when updating role to an invalid value'
);

-- Should allow demoting an admin when another accepted admin remains
select lives_ok(
    format(
        $$select update_group_team_member_role(null::uuid, %L::uuid, %L::uuid, 'viewer')$$,
        :'groupID', :'user1ID'
    ),
    'Should allow demotion when another accepted admin exists'
);

-- Should block demoting the last accepted group admin
select throws_ok(
    format(
        $$select update_group_team_member_role(null::uuid, %L::uuid, %L::uuid, 'viewer')$$,
        :'groupID', :'user2ID'
    ),
    'cannot change role for the last accepted group admin',
    'Should block demoting the last accepted group admin'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
