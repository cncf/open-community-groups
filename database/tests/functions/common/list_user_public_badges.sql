-- Tests community-scoped public profile badge listings.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b0040000-0000-0000-0000-000000000001'
\set groupCategoryID 'b0040000-0000-0000-0000-000000000002'
\set groupID 'b0040000-0000-0000-0000-000000000003'
\set statusListID 'b0040000-0000-0000-0000-000000000004'
\set userBadgeHiddenID 'b0040000-0000-0000-0000-000000000005'
\set userBadgeListedID 'b0040000-0000-0000-0000-000000000006'
\set userID 'b0040000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User whose public badges are requested
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'profile@example.test', true, 'profile-user');

-- Community that contains the issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Profile Community', '/logo', 'profile-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the badges
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Profile Group', 'profile-group');

-- Status list referenced by both awards
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Listed and hidden active awards
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, is_listed, snapshot, status_list_index,
    user_id
) values
    (:'userBadgeListedID', :'statusListID', 0, :'groupID', true, '{"name":"Listed"}', 1, :'userID'),
    (:'userBadgeHiddenID', :'statusListID', 1, :'groupID', false, '{"name":"Hidden"}', 2, :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only listed active badges in the requested community
select is(
    jsonb_array_length(list_user_public_badges(:'communityID', 'PROFILE-USER')::jsonb),
    1,
    'Should return only listed active badges in the requested community'
);

-- Should return an empty list for an unknown user
select is(
    list_user_public_badges(:'communityID', 'missing')::jsonb,
    '[]'::jsonb,
    'Should return an empty list for an unknown user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
