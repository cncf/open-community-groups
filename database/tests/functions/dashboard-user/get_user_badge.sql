-- Tests reading one active dashboard user badge.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b2010000-0000-0000-0000-000000000001'
\set groupCategoryID 'b2010000-0000-0000-0000-000000000002'
\set groupID 'b2010000-0000-0000-0000-000000000003'
\set otherUserID 'b2010000-0000-0000-0000-000000000004'
\set statusListID 'b2010000-0000-0000-0000-000000000005'
\set userBadgeID 'b2010000-0000-0000-0000-000000000006'
\set userID 'b2010000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Badge owner and another dashboard user
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'otherUserID', 'hash', 'get-other@example.test', true, 'get-other'),
    (:'userID', 'hash', 'get-owner@example.test', true, 'get-owner');

-- Community that owns the issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Get Badge Community', '/logo', 'get-badge-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the badge
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Get Badge Group', 'get-badge-group');

-- Status list containing the active award
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active award owned by the dashboard user
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    user_id
) values (:'userBadgeID', :'statusListID', 0, :'groupID', '{"name":"Badge"}', 1, :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return an active badge owned by the user
select is((get_user_badge(:'userID', :'userBadgeID')::jsonb)->>'user_badge_id', :'userBadgeID', 'Should return an active badge owned by the user');

-- Should not return another user's badge
select is(get_user_badge(:'otherUserID', :'userBadgeID')::jsonb, null::jsonb, 'Should not return another user''s badge');

-- Should not return an unknown badge
select is(get_user_badge(:'userID', gen_random_uuid())::jsonb, null::jsonb, 'Should not return an unknown badge');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
