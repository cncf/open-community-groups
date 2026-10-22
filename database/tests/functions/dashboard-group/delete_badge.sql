-- Tests deleting group badge definitions without deleting issued credentials.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

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
select fx_user(:'actorID', jsonb_build_object('username', 'delete-badge-actor'));
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

-- Should remove the definition
select is(
    (select count(*)::integer from badge where badge_id = :'badgeID'),
    0,
    'Should remove the definition'
);

-- Should retain the issued credential with its snapshot name
select results_eq(
    format(
        $$ select badge_id, snapshot from user_badge where user_badge_id = %L::uuid $$,
        :'userBadgeID'
    ),
    $$ values (null::uuid, '{"name":"Badge"}'::jsonb) $$,
    'Should retain the issued credential with its snapshot name'
);

-- Should audit the definition deletion for the actor
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            created_at,
            details,
            event_id,
            group_id,
            resource_id,
            resource_type
        from audit_log
    $$,
    format(
        $$ values (
            'badge_deleted',
            %L::uuid,
            'delete-badge-actor',
            %L::uuid,
            current_timestamp,
            '{"badge_name":"Badge"}'::jsonb,
            null::uuid,
            %L::uuid,
            %L::uuid,
            'badge'
        ) $$,
        :'actorID', :'communityID', :'groupID', :'badgeID'
    ),
    'Should audit the definition deletion for the actor'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
