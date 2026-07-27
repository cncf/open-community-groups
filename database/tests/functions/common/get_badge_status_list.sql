-- Tests public badge status-list reads.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b0020000-0000-0000-0000-000000000001'
\set groupCategoryID 'b0020000-0000-0000-0000-000000000002'
\set groupID 'b0020000-0000-0000-0000-000000000003'
\set statusListID 'b0020000-0000-0000-0000-000000000004'
\set userBadgeActiveID 'b0020000-0000-0000-0000-000000000005'
\set userBadgeRevokedID 'b0020000-0000-0000-0000-000000000006'
\set userID 'b0020000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active recipient used to distinguish the unrevoked bit
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'status@example.test', true, 'status-user');

-- Community that owns the status list
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Status Community', '/logo', 'status-community');

-- Category used by the status group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the status list
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Status Group', 'status-group');

-- Stable group status list
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active and revoked indexes on the same status list
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    revocation_reason, revoked_at, user_id
) values
    (:'userBadgeActiveID', :'statusListID', 0, :'groupID', '{}'::jsonb, 7, null, null, :'userID'),
    (:'userBadgeRevokedID', :'statusListID', 1, :'groupID', '{}'::jsonb, 42, 'revoked', current_timestamp, null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return a complete status list contract with only revoked indexes
select is(
    get_badge_status_list(:'statusListID')::jsonb,
    jsonb_build_object(
        'badge_status_list_id', :'statusListID'::uuid,
        'group_id', :'groupID'::uuid,
        'revoked_indexes', jsonb_build_array(42)
    ),
    'Should return a complete status list contract with only revoked indexes'
);

-- Should return null for an unknown status list
select is(get_badge_status_list(gen_random_uuid())::jsonb, null::jsonb, 'Should return null for an unknown status list');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
