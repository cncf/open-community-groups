-- Tests list_group_admin_ids recipient exclusions including community admins.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedAdminID 'e5160000-0000-0000-0000-000000000001'
\set communityAdminID 'e5160000-0000-0000-0000-000000000002'
\set communityID 'e5160000-0000-0000-0000-000000000003'
\set groupCategoryID 'e5160000-0000-0000-0000-000000000004'
\set groupID 'e5160000-0000-0000-0000-000000000005'
\set managerID 'e5160000-0000-0000-0000-000000000006'
\set unacceptedAdminID 'e5160000-0000-0000-0000-000000000007'
\set unverifiedAdminID 'e5160000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group, and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'acceptedAdminID');
select fx_user(:'communityAdminID');
select fx_user(:'managerID');
select fx_user(:'unacceptedAdminID');
select fx_user(:'unverifiedAdminID', jsonb_build_object('email_verified', false));

-- Community admin is authorized elsewhere but is not a group notification recipient
insert into community_team (accepted, community_id, role, user_id)
values (true, :'communityID', 'admin', :'communityAdminID');

-- Group team rows covering every recipient exclusion
insert into group_team (accepted, group_id, role, user_id) values
    (true, :'groupID', 'admin', :'acceptedAdminID'),
    (true, :'groupID', 'events-manager', :'managerID'),
    (false, :'groupID', 'admin', :'unacceptedAdminID'),
    (true, :'groupID', 'admin', :'unverifiedAdminID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include only accepted verified group admins
select is(
    list_group_admin_ids(:'groupID'::uuid),
    array[:'acceptedAdminID'::uuid],
    'Should include only accepted verified group admins'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
