-- Tests dashboard user badge profile listing changes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b2030000-0000-0000-0000-000000000001'
\set groupCategoryID 'b2030000-0000-0000-0000-000000000002'
\set groupID 'b2030000-0000-0000-0000-000000000003'
\set otherUserID 'b2030000-0000-0000-0000-000000000004'
\set statusListID 'b2030000-0000-0000-0000-000000000005'
\set userBadgeID 'b2030000-0000-0000-0000-000000000006'
\set userID 'b2030000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'otherUserID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Status list containing the active award
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active listed award updated by the test
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    user_id
) values (:'userBadgeID', :'statusListID', 0, :'groupID', '{"name":"Badge"}', 1, :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should hide an active owned badge from profile discovery
select lives_ok(
    format($$select update_user_badge_listing(%L::uuid, %L::uuid, false)$$, :'userID', :'userBadgeID'),
    'Should hide an active owned badge from profile discovery'
);

-- Should persist the listing choice
select is((select is_listed from user_badge where user_badge_id = :'userBadgeID'), false, 'Should persist the listing choice');

-- Should reject a badge owned by another user
select throws_ok(
    format($$select update_user_badge_listing(%L::uuid, %L::uuid, true)$$, :'otherUserID', :'userBadgeID'),
    'OCG01',
    'active awarded badge not found',
    'Should reject a badge owned by another user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
