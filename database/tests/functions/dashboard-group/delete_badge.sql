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


-- Community that owns the badge
select fx_community(:'communityID', jsonb_build_object('description', 'Description'));

-- Baseline categories, users and groups
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'actorID');
select fx_user(:'recipientID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

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
