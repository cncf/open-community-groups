-- Tests badge image retention lookups.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set badgeID 'b0010000-0000-0000-0000-000000000001'
\set communityID 'b0010000-0000-0000-0000-000000000002'
\set groupCategoryID 'b0010000-0000-0000-0000-000000000003'
\set groupID 'b0010000-0000-0000-0000-000000000004'
\set statusListID 'b0010000-0000-0000-0000-000000000005'
\set userBadgeID 'b0010000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns the badge group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Badge Community', '/logo', 'badge-community');

-- Category used by the badge group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that retains badge images
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Badge Group', 'badge-group');

-- Gallery artwork retained without a definition
insert into badge_artwork (file_name, group_id)
values ('gallery.png', :'groupID');

-- Definition artwork retained by a current badge
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Criteria', 'Description', :'groupID', 'definition.png', 'Badge');

-- Status list used by historical issuance data
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Historical snapshot retaining deleted gallery artwork
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    badge_id, revocation_reason, revoked_at
) values (
    :'userBadgeID', :'statusListID', 0, :'groupID',
    '{"criteria":"Criteria","description":"Description","image_file_name":"snapshot.png","issuer":{"community_id":"b0010000-0000-0000-0000-000000000002","community_name":"Badge Community","group_id":"b0010000-0000-0000-0000-000000000004","group_name":"Badge Group"},"name":"Badge"}',
    0, :'badgeID', 'test revocation', current_timestamp
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should recognize artwork gallery images
select is(is_badge_image('gallery.png'), true, 'Should recognize artwork gallery images');

-- Should recognize badge definition images
select is(is_badge_image('definition.png'), true, 'Should recognize badge definition images');

-- Should recognize issuance snapshot images
select is(is_badge_image('snapshot.png'), true, 'Should recognize issuance snapshot images');

-- Should reject unrelated images
select is(is_badge_image('missing.png'), false, 'Should reject unrelated images');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
