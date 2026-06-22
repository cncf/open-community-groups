-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '2c080000-0000-0000-0000-000000000001'
\set user1ID '2c080000-0000-0000-0000-000000000002'
\set user2ID '2c080000-0000-0000-0000-000000000003'
\set user3ID '2c080000-0000-0000-0000-000000000004'
\set user4ID '2c080000-0000-0000-0000-000000000005'

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
    'delete-team-member-alliance',
    'Delete Team Member Alliance',
    'Alliance for deleting team members',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'user1ID', gen_random_bytes(32), 'alice@example.com', true, 'alice', 'Alice'
), (
    :'user2ID', gen_random_bytes(32), 'bob@example.com', true, 'bob', 'Bob'
), (
    :'user3ID', gen_random_bytes(32), 'charlie@example.com', true, 'charlie', 'Charlie'
);

-- Alliance team
insert into alliance_team (alliance_id, user_id, accepted, role) values
    (:'allianceID', :'user1ID', true, 'admin'),
    (:'allianceID', :'user2ID', true, 'admin'),
    (:'allianceID', :'user3ID', false, 'viewer');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow deleting an accepted member when another accepted member remains
select lives_ok(
    format(
        $$ select delete_alliance_team_member(null::uuid, %L::uuid, %L::uuid) $$,
        :'allianceID',
        :'user2ID'
    ),
    'Should allow deleting an accepted member when another accepted member exists'
);
select results_eq(
    format(
        $$ select count(*) from alliance_team where alliance_id = %L::uuid and user_id = %L::uuid $$,
        :'allianceID',
        :'user2ID'
    ),
    $$ values (0::bigint) $$,
    'Deleted accepted membership row should be removed'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            alliance_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'alliance_team_member_removed',
            null::uuid,
            null::text,
            %L::uuid,
            'user',
            %L::uuid
        )
        $$,
        :'allianceID',
        :'user2ID'
    ),
    'Should create the expected audit row'
);

-- Should allow deleting a pending invitation when there is one accepted member left
select lives_ok(
    format(
        $$ select delete_alliance_team_member(null::uuid, %L::uuid, %L::uuid) $$,
        :'allianceID',
        :'user3ID'
    ),
    'Should allow deleting a pending invitation with only one accepted member left'
);

-- Should block deleting the last accepted member
select throws_ok(
    format(
        $$ select delete_alliance_team_member(null::uuid, %L::uuid, %L::uuid) $$,
        :'allianceID',
        :'user1ID'
    ),
    'cannot remove the last accepted alliance admin',
    'Should block deleting the last accepted member'
);
select results_eq(
    format(
        $$ select count(*) from alliance_team where alliance_id = %L::uuid and user_id = %L::uuid $$,
        :'allianceID',
        :'user1ID'
    ),
    $$ values (1::bigint) $$,
    'Last accepted membership row should remain after blocked delete'
);

-- Should not allow deleting when membership does not exist
select throws_ok(
    format(
        $$ select delete_alliance_team_member(null::uuid, %L::uuid, %L::uuid) $$,
        :'allianceID',
        :'user4ID'
    ),
    'user is not a alliance team member',
    'Should not allow deleting when membership does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
