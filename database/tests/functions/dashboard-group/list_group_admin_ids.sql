-- Tests listing accepted, email-verified group admin user ids.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adminID 'e5060000-0000-0000-0000-000000000001'
\set communityAdminID 'e5060000-0000-0000-0000-000000000002'
\set communityID 'e5060000-0000-0000-0000-000000000003'
\set groupCategoryID 'e5060000-0000-0000-0000-000000000004'
\set groupID 'e5060000-0000-0000-0000-000000000005'
\set managerID 'e5060000-0000-0000-0000-000000000006'
\set otherGroupAdminID 'e5060000-0000-0000-0000-000000000007'
\set otherGroupID 'e5060000-0000-0000-0000-000000000008'
\set secondAdminID 'e5060000-0000-0000-0000-000000000009'
\set unacceptedAdminID 'e5060000-0000-0000-0000-00000000000a'
\set unverifiedAdminID 'e5060000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and category
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Baseline group and another group in the same community
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Users covering recipient eligibility states
select fx_user(:'adminID', jsonb_build_object('email_verified', true));
select fx_user(:'communityAdminID', jsonb_build_object('email_verified', true));
select fx_user(:'managerID', jsonb_build_object('email_verified', true));
select fx_user(:'otherGroupAdminID', jsonb_build_object('email_verified', true));
select fx_user(:'secondAdminID', jsonb_build_object('email_verified', true));
select fx_user(:'unacceptedAdminID', jsonb_build_object('email_verified', true));
select fx_user(:'unverifiedAdminID', jsonb_build_object('email_verified', false));

-- Community admin is authorized elsewhere but is not a group recipient
insert into community_team (accepted, community_id, role, user_id)
values (true, :'communityID', 'admin', :'communityAdminID');

-- Accepted verified admin inserted before the lower-id admin to prove ordering
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'admin', :'secondAdminID');

-- Accepted verified admin with the lowest user id
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'admin', :'adminID');

-- Accepted events manager excluded by role
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'events-manager', :'managerID');

-- Pending admin excluded until accepted
insert into group_team (accepted, group_id, role, user_id)
values (false, :'groupID', 'admin', :'unacceptedAdminID');

-- Accepted admin excluded by an unverified email
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'admin', :'unverifiedAdminID');

-- Accepted verified admin of another group excluded by scope
insert into group_team (accepted, group_id, role, user_id)
values (true, :'otherGroupID', 'admin', :'otherGroupAdminID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return accepted, verified group admin user ids ordered by user id
select is(
    list_group_admin_ids(:'groupID'::uuid),
    array[:'adminID'::uuid, :'secondAdminID'::uuid],
    'Should return accepted, verified group admin user ids ordered by user id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
