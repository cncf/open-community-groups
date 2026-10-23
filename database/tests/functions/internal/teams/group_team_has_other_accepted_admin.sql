-- Tests checking whether a group team has another accepted admin.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'a11a0000-0000-0000-0000-000000000001'
\set groupCategoryID 'a11a0000-0000-0000-0000-000000000002'
\set groupDifferentTeamID 'a11a0000-0000-0000-0000-000000000003'
\set groupNonAdminID 'a11a0000-0000-0000-0000-000000000004'
\set groupOnlyTargetID 'a11a0000-0000-0000-0000-000000000005'
\set groupOtherAdminID 'a11a0000-0000-0000-0000-000000000006'
\set groupPendingAdminID 'a11a0000-0000-0000-0000-000000000007'
\set groupSiblingID 'a11a0000-0000-0000-0000-000000000008'
\set otherUserID 'a11a0000-0000-0000-0000-000000000009'
\set targetUserID 'a11a0000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and group category
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Target member and the other team member
select fx_user(:'otherUserID');
select fx_user(:'targetUserID');

-- Groups for each team scenario
select fx_group(:'groupDifferentTeamID', :'communityID', :'groupCategoryID');
select fx_group(:'groupNonAdminID', :'communityID', :'groupCategoryID');
select fx_group(:'groupOnlyTargetID', :'communityID', :'groupCategoryID');
select fx_group(:'groupOtherAdminID', :'communityID', :'groupCategoryID');
select fx_group(:'groupPendingAdminID', :'communityID', :'groupCategoryID');
select fx_group(:'groupSiblingID', :'communityID', :'groupCategoryID');

-- Team whose only other accepted admin belongs to a sibling group
insert into group_team (group_id, user_id, role, accepted)
values (:'groupDifferentTeamID', :'targetUserID', 'admin', true);

-- Team with the target admin and another accepted viewer
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupNonAdminID', :'otherUserID', 'viewer', true),
    (:'groupNonAdminID', :'targetUserID', 'admin', true);

-- Team with the target as its only accepted admin
insert into group_team (group_id, user_id, role, accepted)
values (:'groupOnlyTargetID', :'targetUserID', 'admin', true);

-- Team with the target admin and another accepted admin
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupOtherAdminID', :'otherUserID', 'admin', true),
    (:'groupOtherAdminID', :'targetUserID', 'admin', true);

-- Team with the target admin and another pending admin
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupPendingAdminID', :'otherUserID', 'admin', false),
    (:'groupPendingAdminID', :'targetUserID', 'admin', true);

-- Sibling team with another accepted admin
insert into group_team (group_id, user_id, role, accepted)
values (:'groupSiblingID', :'otherUserID', 'admin', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore accepted admins of a different team
select is(
    group_team_has_other_accepted_admin(:'groupDifferentTeamID'::uuid, :'targetUserID'::uuid),
    false,
    'Should ignore accepted admins of a different team'
);

-- Should ignore other accepted members without the admin role
select is(
    group_team_has_other_accepted_admin(:'groupNonAdminID'::uuid, :'targetUserID'::uuid),
    false,
    'Should ignore other accepted members without the admin role'
);

-- Should ignore other pending admins
select is(
    group_team_has_other_accepted_admin(:'groupPendingAdminID'::uuid, :'targetUserID'::uuid),
    false,
    'Should ignore other pending admins'
);

-- Should return false when the target is the only accepted admin
select is(
    group_team_has_other_accepted_admin(:'groupOnlyTargetID'::uuid, :'targetUserID'::uuid),
    false,
    'Should return false when the target is the only accepted admin'
);

-- Should return true when another accepted admin exists
select is(
    group_team_has_other_accepted_admin(:'groupOtherAdminID'::uuid, :'targetUserID'::uuid),
    true,
    'Should return true when another accepted admin exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
