-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

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
select fx_user(:'userID', jsonb_build_object('username', 'alice-reject-group-team-invitation'));

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

-- Should reject a second rejection when no pending invitation exists
select throws_ok(
    format(
        $$
            select reject_group_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'userID',
        :'groupID'
    ),
    'OCG01',
    'no pending group invitation found',
    'Should reject a second rejection when no pending invitation exists'
);

-- Should not create an audit row when the rejection fails
select is(
    (select count(*)::int from audit_log),
    1,
    'Should not create an audit row when the rejection fails'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
