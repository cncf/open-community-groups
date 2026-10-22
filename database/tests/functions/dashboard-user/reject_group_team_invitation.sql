-- Tests rejecting a pending group team invitation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedUserID '4a120000-0000-0000-0000-000000000005'
\set communityID '4a120000-0000-0000-0000-000000000001'
\set groupCategoryID '4a120000-0000-0000-0000-000000000002'
\set groupID '4a120000-0000-0000-0000-000000000003'
\set userID '4a120000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'acceptedUserID');
select fx_user(:'userID', jsonb_build_object('username', 'alice-reject-group-team-invitation'));

-- Accepted membership that is not a pending invitation
insert into group_team (group_id, user_id, role, accepted)
values (:'groupID', :'acceptedUserID', 'admin', true);

-- Pending invitation
insert into group_team (group_id, user_id, role, accepted)
values (:'groupID', :'userID', 'admin', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should remove the pending group invitation
select lives_ok(
    format(
        $$
            select reject_group_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'userID',
        :'groupID'
    ),
    'Should remove the pending group invitation'
);

-- Should delete the pending group invitation row
select is(
    (
        select count(*)::int
        from group_team
        where group_id = :'groupID'::uuid
        and user_id = :'userID'::uuid
    ),
    0,
    'Should delete the pending group invitation row'
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
                'group_team_invitation_rejected',
                %L::uuid,
                'alice-reject-group-team-invitation',
                %L::uuid,
                %L::uuid,
                'user',
                %L::uuid
            )
        $$,
        :'userID',
        :'communityID',
        :'groupID',
        :'userID'
    ),
    'Should create the expected audit row'
);

-- Should reject an accepted membership as no pending invitation
select throws_ok(
    format(
        $$
            select reject_group_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'acceptedUserID',
        :'groupID'
    ),
    'OCG01',
    'no pending group invitation found',
    'Should reject an accepted membership as no pending invitation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
