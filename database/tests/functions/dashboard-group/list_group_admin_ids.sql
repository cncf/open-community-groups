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
\set communityID 'e5060000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5060000-0000-0000-0000-000000000003'
\set groupCategoryID 'e5060000-0000-0000-0000-000000000004'
\set groupID 'e5060000-0000-0000-0000-000000000005'
\set managerID 'e5060000-0000-0000-0000-000000000006'
\set unacceptedAdminID 'e5060000-0000-0000-0000-000000000007'
\set unverifiedAdminID 'e5060000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and categories
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Baseline group
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users covering recipient eligibility states
select fx_user(:'adminID');
select fx_user(:'managerID');
select fx_user(:'unacceptedAdminID');
select fx_user(:'unverifiedAdminID', jsonb_build_object('email_verified', false));

-- Group team memberships covering recipient eligibility states
insert into group_team (group_id, user_id, accepted, role) values
    (:'groupID', :'adminID', true, 'admin'),
    (:'groupID', :'managerID', true, 'events-manager'),
    (:'groupID', :'unacceptedAdminID', false, 'admin'),
    (:'groupID', :'unverifiedAdminID', true, 'admin');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return accepted, verified group admin user ids ordered by user id
select is(
    list_group_admin_ids(:'groupID'::uuid),
    array[:'adminID'::uuid],
    'Should return accepted, verified group admin user ids ordered by user id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
