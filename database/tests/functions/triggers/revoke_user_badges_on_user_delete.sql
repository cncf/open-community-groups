-- Tests durable badge revocation when a recipient account is deleted.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ba010000-0000-0000-0000-000000000001'
\set groupCategoryID 'ba010000-0000-0000-0000-000000000002'
\set groupID 'ba010000-0000-0000-0000-000000000003'
\set statusListID 'ba010000-0000-0000-0000-000000000004'
\set userBadgeID 'ba010000-0000-0000-0000-000000000005'
\set userID 'ba010000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Badge recipient account
insert into "user" (auth_hash, email, email_verified, user_id, username)
values ('account-delete-hash', 'account-delete@example.test', true, :'userID', 'account-delete-user');

-- Issuing community
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    '/mobile',
    '/banner',
    :'communityID',
    'Description',
    'Account Delete Community',
    '/logo',
    'account-delete-community'
);

-- Issuing group category
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Issuing group retained by credential history
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Account Delete Group', 'account-delete-group');

-- Stable status list retained after account deletion
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active award associated with the account being deleted
insert into user_badge (
    badge_status_list_id,
    display_order,
    group_id,
    snapshot,
    status_list_index,
    user_badge_id,

    user_id
) values (
    :'statusListID',
    0,
    :'groupID',
    '{"name":"Account Delete Badge"}',
    42,
    :'userBadgeID',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow deleting a recipient with an active badge
select lives_ok(
    format($$delete from "user" where user_id = %L::uuid$$, :'userID'),
    'Should allow deleting a badge recipient account'
);

-- Should clear the internal recipient association after revoking
select is(
    (select user_id from user_badge where user_badge_id = :'userBadgeID'),
    null,
    'Should clear the deleted recipient association'
);

-- Should publish an irreversible revocation and clear profile listing
select ok(
    exists (
        select 1
        from user_badge
        where user_badge_id = :'userBadgeID'
        and is_listed = false
        and revocation_reason = 'recipient account deleted'
        and revoked_at is not null
        and revoked_by_user_id is null
    ),
    'Should revoke the active credential before clearing its user'
);

-- Should retain one durable lifecycle audit row with the username snapshot
select ok(
    exists (
        select 1
        from audit_log
        where action = 'badge_revoked_account_deleted'
        and actor_username = 'account-delete-user'
        and resource_id = :'userBadgeID'
    ),
    'Should record account-deletion revocation history'
);

-- Should not enqueue a recipient notification for account deletion
select is(
    (select count(*)::integer from notification where kind = 'badge-revoked'),
    0,
    'Should not enqueue an account-deletion revocation notification'
);

-- Should retain the public status-list row and revoked index
select is(
    get_badge_status_list(:'statusListID')::jsonb->'revoked_indexes',
    '[42]'::jsonb,
    'Should retain the revoked bit through the public status-list function'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
