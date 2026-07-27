-- Tests deleting group badge definitions without deleting issued credentials.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'b1060000-0000-0000-0000-000000000001'
\set badgeID 'b1060000-0000-0000-0000-000000000002'
\set communityID 'b1060000-0000-0000-0000-000000000003'
\set groupCategoryID 'b1060000-0000-0000-0000-000000000004'
\set groupID 'b1060000-0000-0000-0000-000000000005'
\set recipientID 'b1060000-0000-0000-0000-000000000006'
\set statusListID 'b1060000-0000-0000-0000-000000000007'
\set userBadgeID 'b1060000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Admin and credential recipient
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'actorID', 'hash', 'delete-admin@example.test', true, 'delete-admin'),
    (:'recipientID', 'hash', 'delete-recipient@example.test', true, 'delete-recipient');

-- Community that owns the badge
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Delete Community', '/logo', 'delete-community');

-- Category used by the badge group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the badge
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Delete Group', 'delete-group');

-- Authorized group team member
insert into group_team (group_id, accepted, role, user_id)
values (:'groupID', true, 'admin', :'actorID');

-- Definition deleted by the test
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Criteria', 'Description', :'groupID', 'badge.png', 'Badge');

-- Status list retained by the credential
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Credential snapshot retained after definition deletion
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    badge_id, user_id
) values (:'userBadgeID', :'statusListID', 0, :'groupID', '{"name":"Badge"}', 1, :'badgeID', :'recipientID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete the definition while retaining the credential snapshot
select lives_ok(
    format($$select delete_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'communityID', :'groupID', :'badgeID'),
    'Should delete the definition while retaining the credential snapshot'
);

-- Should retain the issued credential and audit the deletion
select ok(
    not exists (select 1 from badge where badge_id = :'badgeID')
    and exists (select 1 from user_badge where user_badge_id = :'userBadgeID' and badge_id is null and snapshot->>'name' = 'Badge')
    and exists (
        select 1 from audit_log
        where action = 'badge_deleted'
        and details = '{"badge_name":"Badge"}'::jsonb
    ),
    'Should retain the issued credential and audit the deletion'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
