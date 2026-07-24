-- Tests public badge credential record reads.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b0030000-0000-0000-0000-000000000001'
\set groupCategoryID 'b0030000-0000-0000-0000-000000000002'
\set groupID 'b0030000-0000-0000-0000-000000000003'
\set statusListID 'b0030000-0000-0000-0000-000000000004'
\set userBadgeID 'b0030000-0000-0000-0000-000000000005'
\set userID 'b0030000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Current recipient associated with the opaque credential
insert into "user" (user_id, auth_hash, email, email_verified, username, name)
values (:'userID', 'hash', 'recipient@example.test', true, 'recipient', 'Recipient');

-- Community that issued the credential
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Public Community', '/logo', 'public-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the credential
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Public Group', 'public-group');

-- Status list referenced by the credential
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Durable credential record
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    user_id
) values (:'userBadgeID', :'statusListID', 0, :'groupID', '{"name":"Badge"}', 9, :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return durable and current recipient fields
select ok(
    get_public_user_badge(:'userBadgeID')::jsonb @> jsonb_build_object(
        'recipient_name', 'Recipient',
        'recipient_username', 'recipient',
        'status_list_index', 9,
        'user_badge_id', :'userBadgeID'::uuid
    ),
    'Should return durable and current recipient fields'
);

-- Should return null for an unknown credential
select is(get_public_user_badge(gen_random_uuid())::jsonb, null::jsonb, 'Should return null for an unknown credential');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
