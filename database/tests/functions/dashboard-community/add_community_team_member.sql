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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'team-member-community',
    'Team Member Community',
    'Community for team member tests',
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
) values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', true, 'alice', 'Alice'),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', true, 'bob', 'Bob');

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
    'user is already a community team member',
    'Should not allow duplicate community team membership'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
