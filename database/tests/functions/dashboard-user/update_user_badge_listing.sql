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

-- Badge owner and another dashboard user
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'otherUserID', 'hash', 'listing-other@example.test', true, 'listing-other'),
    (:'userID', 'hash', 'listing-owner@example.test', true, 'listing-owner');

-- Community that owns the issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Listing Community', '/logo', 'listing-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the badge
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Listing Group', 'listing-group');

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
    'active awarded badge not found',
    'Should reject a badge owned by another user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
