-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a260000-0000-0000-0000-000000000001'
\set groupCategoryID '3a260000-0000-0000-0000-000000000002'
\set groupID '3a260000-0000-0000-0000-000000000003'
\set missingGroupID '3a260000-0000-0000-0000-000000000004'
\set user1ID '3a260000-0000-0000-0000-000000000005'
\set user2ID '3a260000-0000-0000-0000-000000000006'
\set user3ID '3a260000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID');
select fx_user(:'user2ID', jsonb_build_object('email_verified', false));
select fx_user(:'user3ID');

-- Group team
insert into group_team (group_id, user_id, accepted, role)
values
    (:'groupID', :'user1ID', true, 'admin'),
    (:'groupID', :'user2ID', true, 'admin'),
    (:'groupID', :'user3ID', false, 'admin');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return accepted, verified team member user ids ordered by user id
select is(
    list_group_team_members_ids(:'groupID'::uuid),
    array[:'user1ID'::uuid],
    'Should return accepted, verified team member user ids ordered by user id'
);

-- Should return empty list for non-existing group
select is(
    list_group_team_members_ids(:'missingGroupID'::uuid),
    array[]::uuid[],
    'Should return empty list for non-existing group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
