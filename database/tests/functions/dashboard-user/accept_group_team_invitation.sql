-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a030000-0000-0000-0000-000000000001'
\set groupCategoryID '4a030000-0000-0000-0000-000000000002'
\set groupID '4a030000-0000-0000-0000-000000000003'
\set user1ID '4a030000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID', jsonb_build_object('username', 'alice-accept-group-team-invitation'));

-- Pending invitation
insert into group_team (group_id, user_id, role, accepted)
values (:'groupID', :'user1ID', 'admin', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should flip accepted to true when accepting pending invite
select lives_ok(
    format(
        $$
            select accept_group_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'user1ID',
        :'groupID'
    ),
    'Should succeed for pending invite'
);
select results_eq(
    format(
        $$
            select accepted
            from group_team
            where group_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'groupID',
        :'user1ID'
    ),
    $$ values (true) $$,
    'Invite should be marked as accepted'
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
                'group_team_invitation_accepted',
                %L::uuid,
                'alice-accept-group-team-invitation',
                %L::uuid,
                %L::uuid,
                'user',
                %L::uuid
            )
        $$,
        :'user1ID',
        :'communityID',
        :'groupID',
        :'user1ID'
    ),
    'Should create the expected audit row'
);

-- Should raise error when no pending invitation exists
select throws_ok(
    format(
        $$
            select accept_group_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'user1ID',
        :'groupID'
    ),
    'OCG01',
    'no pending group invitation found',
    'Second accept should fail since invite is no longer pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
