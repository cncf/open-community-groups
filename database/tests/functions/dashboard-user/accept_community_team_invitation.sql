-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a010000-0000-0000-0000-000000000001'
\set user2ID '4a010000-0000-0000-0000-000000000002'
\set userID '4a010000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and users
select fx_community(:'communityID');
select fx_user(:'user2ID');

-- Users
select fx_user(:'userID', jsonb_build_object('username', 'user-accept-community-team-invitation'));

-- Pending invitation
insert into community_team (
    accepted,
    community_id,
    role,
    user_id
) values (
    false,
    :'communityID',
    'viewer',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should flip accepted to true when accepting invitation
select lives_ok(
    format(
        $$
            select accept_community_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'userID',
        :'communityID'
    ),
    'Should accept a pending community team invitation'
);
select results_eq(
    format(
        $$
            select accepted
            from community_team
            where community_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'communityID',
        :'userID'
    ),
    $$ values (true) $$,
    'Invitation should be marked as accepted'
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
            resource_id
        from audit_log
    $$,
    format(
        $$
            values (
                'community_team_invitation_accepted',
                %L::uuid,
                'user-accept-community-team-invitation',
                %L::uuid,
                'user',
                %L::uuid
            )
        $$,
        :'userID',
        :'communityID',
        :'userID'
    ),
    'Should create the expected audit row'
);

-- Should reject accepting a non-existent invitation
select throws_ok(
    format(
        'select accept_community_team_invitation(%L::uuid, %L::uuid)',
        :'user2ID',
        :'communityID'
    ),
    'OCG01',
    'no pending community invitation found',
    'Should reject accepting a non-existent invitation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
