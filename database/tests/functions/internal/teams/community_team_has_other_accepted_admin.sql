-- Tests checking whether a community team has another accepted admin.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityDifferentTeamID 'a11b0000-0000-0000-0000-000000000001'
\set communityNonAdminID 'a11b0000-0000-0000-0000-000000000002'
\set communityOnlyTargetID 'a11b0000-0000-0000-0000-000000000003'
\set communityOtherAdminID 'a11b0000-0000-0000-0000-000000000004'
\set communityPendingAdminID 'a11b0000-0000-0000-0000-000000000005'
\set communitySiblingID 'a11b0000-0000-0000-0000-000000000006'
\set otherUserID 'a11b0000-0000-0000-0000-000000000007'
\set targetUserID 'a11b0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities for each team scenario
select fx_community(:'communityDifferentTeamID');
select fx_community(:'communityNonAdminID');
select fx_community(:'communityOnlyTargetID');
select fx_community(:'communityOtherAdminID');
select fx_community(:'communityPendingAdminID');
select fx_community(:'communitySiblingID');

-- Target member and the other team member
select fx_user(:'otherUserID');
select fx_user(:'targetUserID');

-- Team whose only other accepted admin belongs to a sibling community
insert into community_team (community_id, user_id, role, accepted)
values (:'communityDifferentTeamID', :'targetUserID', 'admin', true);

-- Team with the target admin and another accepted viewer
insert into community_team (community_id, user_id, role, accepted)
values
    (:'communityNonAdminID', :'otherUserID', 'viewer', true),
    (:'communityNonAdminID', :'targetUserID', 'admin', true);

-- Team with the target as its only accepted admin
insert into community_team (community_id, user_id, role, accepted)
values (:'communityOnlyTargetID', :'targetUserID', 'admin', true);

-- Team with the target admin and another accepted admin
insert into community_team (community_id, user_id, role, accepted)
values
    (:'communityOtherAdminID', :'otherUserID', 'admin', true),
    (:'communityOtherAdminID', :'targetUserID', 'admin', true);

-- Team with the target admin and another pending admin
insert into community_team (community_id, user_id, role, accepted)
values
    (:'communityPendingAdminID', :'otherUserID', 'admin', false),
    (:'communityPendingAdminID', :'targetUserID', 'admin', true);

-- Sibling team with another accepted admin
insert into community_team (community_id, user_id, role, accepted)
values (:'communitySiblingID', :'otherUserID', 'admin', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore accepted admins of a different team
select is(
    community_team_has_other_accepted_admin(:'communityDifferentTeamID'::uuid, :'targetUserID'::uuid),
    false,
    'Should ignore accepted admins of a different team'
);

-- Should ignore other accepted members without the admin role
select is(
    community_team_has_other_accepted_admin(:'communityNonAdminID'::uuid, :'targetUserID'::uuid),
    false,
    'Should ignore other accepted members without the admin role'
);

-- Should ignore other pending admins
select is(
    community_team_has_other_accepted_admin(:'communityPendingAdminID'::uuid, :'targetUserID'::uuid),
    false,
    'Should ignore other pending admins'
);

-- Should return false when the target is the only accepted admin
select is(
    community_team_has_other_accepted_admin(:'communityOnlyTargetID'::uuid, :'targetUserID'::uuid),
    false,
    'Should return false when the target is the only accepted admin'
);

-- Should return true when another accepted admin exists
select is(
    community_team_has_other_accepted_admin(:'communityOtherAdminID'::uuid, :'targetUserID'::uuid),
    true,
    'Should return true when another accepted admin exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
