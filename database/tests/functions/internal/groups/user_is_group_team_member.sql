-- Tests detecting accepted group team members.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1b140000-0000-0000-0000-000000000001'
\set groupCategoryID '1b140000-0000-0000-0000-000000000002'
\set groupID '1b140000-0000-0000-0000-000000000003'
\set otherGroupID '1b140000-0000-0000-0000-000000000005'
\set pendingTeamMemberID '1b140000-0000-0000-0000-000000000006'
\set teamMemberID '1b140000-0000-0000-0000-000000000004'
\set userID '1b140000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Invited team member who has not accepted yet
select fx_user(:'pendingTeamMemberID');

-- Accepted team member
select fx_user(:'teamMemberID');

-- Regular user
select fx_user(:'userID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group whose team is checked
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group whose team includes the regular user
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Accepted viewer membership of the team member
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'viewer', :'teamMemberID');

-- Pending admin membership of the invited team member
insert into group_team (accepted, group_id, role, user_id)
values (false, :'groupID', 'admin', :'pendingTeamMemberID');

-- Accepted admin membership of the regular user in another group
insert into group_team (accepted, group_id, role, user_id)
values (true, :'otherGroupID', 'admin', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should detect accepted team members with any role
select is(
    user_is_group_team_member(:'groupID'::uuid, :'teamMemberID'::uuid),
    true,
    'Should detect accepted team members with any role'
);

-- Should ignore members of other groups
select is(
    user_is_group_team_member(:'groupID'::uuid, :'userID'::uuid),
    false,
    'Should ignore members of other groups'
);

-- Should ignore missing users
select is(
    user_is_group_team_member(:'groupID'::uuid, null),
    false,
    'Should ignore missing users'
);

-- Should ignore pending team invitations
select is(
    user_is_group_team_member(:'groupID'::uuid, :'pendingTeamMemberID'::uuid),
    false,
    'Should ignore pending team invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
