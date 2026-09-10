-- Tests complete keyboard and pointer badge order persistence.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b2040000-0000-0000-0000-000000000001'
\set firstBadgeID 'b2040000-0000-0000-0000-000000000002'
\set groupCategoryID 'b2040000-0000-0000-0000-000000000003'
\set groupID 'b2040000-0000-0000-0000-000000000004'
\set secondBadgeID 'b2040000-0000-0000-0000-000000000005'
\set statusListID 'b2040000-0000-0000-0000-000000000006'
\set userID 'b2040000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Status list used by both active awards
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Two active awards in their initial order
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    user_id
) values
    (:'firstBadgeID', :'statusListID', 0, :'groupID', '{"name":"First"}', 1, :'userID'),
    (:'secondBadgeID', :'statusListID', 1, :'groupID', '{"name":"Second"}', 2, :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should persist a complete zero-based order
select lives_ok(
    format($$select update_user_badges_order(%L::uuid, array[%L::uuid, %L::uuid])$$, :'userID', :'secondBadgeID', :'firstBadgeID'),
    'Should persist a complete zero-based order'
);

-- Should return badges in the persisted order
select results_eq(
    format($$select user_badge_id from user_badge where user_id = %L order by display_order$$, :'userID'),
    format($$values (%L::uuid), (%L::uuid)$$, :'secondBadgeID', :'firstBadgeID'),
    'Should return badges in the persisted order'
);

-- Should reject duplicate or incomplete orders
select throws_ok(
    format($$select update_user_badges_order(%L::uuid, array[%L::uuid, %L::uuid])$$, :'userID', :'firstBadgeID', :'firstBadgeID'),
    'OCG01',
    'badge order does not match active badges',
    'Should reject duplicate or incomplete orders'
);

-- Should reject a missing order instead of treating it as an empty update
select throws_ok(
    format($$select update_user_badges_order(%L::uuid, null)$$, :'userID'),
    'OCG01',
    'badge order does not match active badges',
    'Should reject a missing order'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
