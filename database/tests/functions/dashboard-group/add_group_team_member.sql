-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a050000-0000-0000-0000-000000000001'
\set groupCategoryID '3a050000-0000-0000-0000-000000000002'
\set groupID '3a050000-0000-0000-0000-000000000003'
\set user1ID '3a050000-0000-0000-0000-000000000004'
\set user2ID '3a050000-0000-0000-0000-000000000005'

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
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Test Group', 'test-group');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'user1ID',
    gen_random_bytes(32),
    'alice@example.com',
    true,
    'alice',
    'Alice'
), (
    :'user2ID',
    gen_random_bytes(32),
    'carol@example.com',
    true,
    'carol',
    'Carol'
);

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
        :'allianceID', :'groupID', :'user1ID'
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
    'user is already a group team member',
    'Should not allow duplicate group team membership'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
