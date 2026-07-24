-- Tests active dashboard user badge listings.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b2020000-0000-0000-0000-000000000001'
\set groupCategoryID 'b2020000-0000-0000-0000-000000000002'
\set groupID 'b2020000-0000-0000-0000-000000000003'
\set statusListID 'b2020000-0000-0000-0000-000000000004'
\set userID 'b2020000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User who owns active and revoked badge history
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'list-owner@example.test', true, 'list-owner');

-- Community that owns the issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'User List Community', '/logo', 'user-list-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the badges
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'User List Group', 'user-list-group');

-- Status list used by active and revoked awards
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active and revoked award rows
insert into user_badge (
    badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    revocation_reason, revoked_at, user_id
) values
    (:'statusListID', 1, :'groupID', '{"name":"Second"}', 1, null, null, :'userID'),
    (:'statusListID', 0, :'groupID', '{"name":"First"}', 2, null, null, :'userID'),
    (:'statusListID', 2, :'groupID', '{"name":"Revoked"}', 3, 'revoked', current_timestamp, :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list active awards only
select is(jsonb_array_length(list_user_badges(:'userID')::jsonb), 2, 'Should list active awards only');

-- Should respect the persisted display order
select is((list_user_badges(:'userID')::jsonb)->0->'snapshot'->>'name', 'First', 'Should respect the persisted display order');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
