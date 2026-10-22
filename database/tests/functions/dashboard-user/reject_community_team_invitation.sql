-- Tests rejecting a pending community team invitation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedUserID '4a100000-0000-0000-0000-000000000003'
\set communityID '4a100000-0000-0000-0000-000000000001'
\set userID '4a100000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community
select fx_community(:'communityID');

-- Users
select fx_user(:'acceptedUserID');
select fx_user(:'userID', jsonb_build_object('username', 'user-reject-community-team-invitation'));

-- Accepted membership that is not a pending invitation
insert into community_team (
    accepted,
    community_id,
    role,
    user_id
) values (
    true,
    :'communityID',
    'viewer',
    :'acceptedUserID'
);

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

-- Should remove the pending invitation
select lives_ok(
    format(
        $$
            select reject_community_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'userID',
        :'communityID'
    ),
    'Should remove the pending invitation'
);

-- Should delete the pending invitation row
select is(
    (
        select count(*)::int
        from community_team
        where community_id = :'communityID'::uuid
        and user_id = :'userID'::uuid
    ),
    0,
    'Should delete the pending invitation row'
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
                'community_team_invitation_rejected',
                %L::uuid,
                'user-reject-community-team-invitation',
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

-- Should reject an accepted membership as no pending invitation
select throws_ok(
    format(
        $$
            select reject_community_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'acceptedUserID',
        :'communityID'
    ),
    'OCG01',
    'no pending community invitation found',
    'Should reject an accepted membership as no pending invitation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
