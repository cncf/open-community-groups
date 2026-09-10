-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeGroupID '6a040000-0000-0000-0000-000000000001'
\set communityID '6a040000-0000-0000-0000-000000000002'
\set groupCategoryID '6a040000-0000-0000-0000-000000000003'
\set inactiveGroupID '6a040000-0000-0000-0000-000000000004'
\set unknownGroupID '6a040000-0000-0000-0000-000000000005'
\set user1ID '6a040000-0000-0000-0000-000000000006'
\set user2ID '6a040000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, category, users and active group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_group(:'activeGroupID', :'communityID', :'groupCategoryID');

-- Inactive group used for membership rejection
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Group Member (active group)
insert into group_member (group_id, user_id)
values (:'activeGroupID', :'user1ID');

-- Group Member (inactive group)
insert into group_member (group_id, user_id)
values (:'inactiveGroupID', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return true for existing group member
select ok(
    is_group_member(:'communityID'::uuid, :'activeGroupID'::uuid, :'user1ID'::uuid),
    'Should return true for existing group member'
);

-- Should return false for non-member
select ok(
    not is_group_member(:'communityID'::uuid, :'activeGroupID'::uuid, :'user2ID'::uuid),
    'Should return false for non-member'
);

-- Should return false for invalid group
select ok(
    not is_group_member(:'communityID'::uuid, :'unknownGroupID'::uuid, :'user1ID'::uuid),
    'Should return false for invalid group'
);

-- Should return false for inactive group even if user is a member
select ok(
    not is_group_member(:'communityID'::uuid, :'inactiveGroupID'::uuid, :'user1ID'::uuid),
    'Should return false for inactive group even if user is a member'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
