-- Tests listing the verified members and accepted, verified team members of a group.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f8a80000-0000-0000-0000-000000000001'
\set emptyGroupID 'f8a80000-0000-0000-0000-000000000002'
\set groupCategoryID 'f8a80000-0000-0000-0000-000000000003'
\set groupID 'f8a80000-0000-0000-0000-000000000004'
\set memberAndTeamMemberID 'f8a80000-0000-0000-0000-000000000005'
\set memberID 'f8a80000-0000-0000-0000-000000000006'
\set otherGroupID 'f8a80000-0000-0000-0000-000000000007'
\set otherGroupMemberID 'f8a80000-0000-0000-0000-000000000008'
\set otherGroupTeamMemberID 'f8a80000-0000-0000-0000-000000000009'
\set pendingTeamMemberID 'f8a80000-0000-0000-0000-00000000000a'
\set teamMemberID 'f8a80000-0000-0000-0000-00000000000b'
\set unverifiedMemberID 'f8a80000-0000-0000-0000-00000000000c'
\set unverifiedTeamMemberID 'f8a80000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and category
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group under test, a group without audience and another group in the same community
select fx_group(:'emptyGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Users covering audience eligibility states
select fx_user(:'memberAndTeamMemberID', jsonb_build_object('email_verified', true));
select fx_user(:'memberID', jsonb_build_object('email_verified', true));
select fx_user(:'otherGroupMemberID', jsonb_build_object('email_verified', true));
select fx_user(:'otherGroupTeamMemberID', jsonb_build_object('email_verified', true));
select fx_user(:'pendingTeamMemberID', jsonb_build_object('email_verified', true));
select fx_user(:'teamMemberID', jsonb_build_object('email_verified', true));
select fx_user(:'unverifiedMemberID', jsonb_build_object('email_verified', false));
select fx_user(:'unverifiedTeamMemberID', jsonb_build_object('email_verified', false));

-- Verified member inserted before the lower-id member to prove ordering
insert into group_member (group_id, user_id)
values (:'groupID', :'memberID');

-- Verified member who is also an accepted team member
insert into group_member (group_id, user_id)
values (:'groupID', :'memberAndTeamMemberID');

-- Member excluded by an unverified email
insert into group_member (group_id, user_id)
values (:'groupID', :'unverifiedMemberID');

-- Verified member of another group excluded by scope
insert into group_member (group_id, user_id)
values (:'otherGroupID', :'otherGroupMemberID');

-- Accepted verified team member with the highest included user id
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'admin', :'teamMemberID');

-- Accepted verified team member who is also a member
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'events-manager', :'memberAndTeamMemberID');

-- Pending team member excluded until accepted
insert into group_team (accepted, group_id, role, user_id)
values (false, :'groupID', 'admin', :'pendingTeamMemberID');

-- Accepted team member excluded by an unverified email
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'admin', :'unverifiedTeamMemberID');

-- Accepted verified team member of another group excluded by scope
insert into group_team (accepted, group_id, role, user_id)
values (true, :'otherGroupID', 'admin', :'otherGroupTeamMemberID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude members and team members of other groups
select ok(
    not (
        list_group_audience_ids(:'groupID'::uuid)
        && array[:'otherGroupMemberID'::uuid, :'otherGroupTeamMemberID'::uuid]
    ),
    'Should exclude members and team members of other groups'
);

-- Should exclude members with an unverified email
select ok(
    not (:'unverifiedMemberID'::uuid = any(list_group_audience_ids(:'groupID'::uuid))),
    'Should exclude members with an unverified email'
);

-- Should exclude pending team members
select ok(
    not (:'pendingTeamMemberID'::uuid = any(list_group_audience_ids(:'groupID'::uuid))),
    'Should exclude pending team members'
);

-- Should exclude team members with an unverified email
select ok(
    not (:'unverifiedTeamMemberID'::uuid = any(list_group_audience_ids(:'groupID'::uuid))),
    'Should exclude team members with an unverified email'
);

-- Should list a user who is both a member and a team member once
select is(
    cardinality(array_positions(list_group_audience_ids(:'groupID'::uuid), :'memberAndTeamMemberID'::uuid)),
    1,
    'Should list a user who is both a member and a team member once'
);

-- Should return an empty array for a group without audience
select is(
    list_group_audience_ids(:'emptyGroupID'::uuid),
    array[]::uuid[],
    'Should return an empty array for a group without audience'
);

-- Should return verified members and accepted, verified team members ordered by user id
select is(
    list_group_audience_ids(:'groupID'::uuid),
    array[:'memberAndTeamMemberID'::uuid, :'memberID'::uuid, :'teamMemberID'::uuid],
    'Should return verified members and accepted, verified team members ordered by user id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
