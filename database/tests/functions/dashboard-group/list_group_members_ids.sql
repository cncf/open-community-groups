-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a220000-0000-0000-0000-000000000001'
\set groupCategoryID '3a220000-0000-0000-0000-000000000002'
\set groupID '3a220000-0000-0000-0000-000000000003'
\set missingGroupID '3a220000-0000-0000-0000-000000000004'
\set user1ID '3a220000-0000-0000-0000-000000000005'
\set user2ID '3a220000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID');
select fx_user(:'user2ID');

-- Group members
insert into group_member (group_id, user_id, created_at)
values
    (:'groupID', :'user1ID', '2024-01-01 00:00:00+00'),
    (:'groupID', :'user2ID', '2024-01-02 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return members user ids ordered by user id
select is(
    list_group_members_ids(:'groupID'::uuid),
    array[:'user1ID'::uuid, :'user2ID'::uuid],
    'Should return members user ids ordered by user id'
);

-- Should return empty list for non-existing group
select is(
    list_group_members_ids(:'missingGroupID'::uuid),
    array[]::uuid[],
    'Should return empty list for non-existing group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
