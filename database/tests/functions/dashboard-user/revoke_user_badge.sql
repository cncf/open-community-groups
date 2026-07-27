-- Tests irreversible dashboard user badge revocation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b2050000-0000-0000-0000-000000000001'
\set groupCategoryID 'b2050000-0000-0000-0000-000000000002'
\set groupID 'b2050000-0000-0000-0000-000000000003'
\set otherUserID 'b2050000-0000-0000-0000-000000000004'
\set statusListID 'b2050000-0000-0000-0000-000000000005'
\set userBadgeID 'b2050000-0000-0000-0000-000000000006'
\set userID 'b2050000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Badge owner and another dashboard user
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'otherUserID', 'hash', 'self-revoke-other@example.test', true, 'self-revoke-other'),
    (:'userID', 'hash', 'self-revoke-owner@example.test', true, 'self-revoke-owner');

-- Community that owns the issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Self Revoke Community', '/logo', 'self-revoke-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the badge
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Self Revoke Group', 'self-revoke-group');

-- Status list containing the active award
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active award revoked by its recipient
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    user_id
) values (:'userBadgeID', :'statusListID', 0, :'groupID', '{"name":"Badge"}', 1, :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject another user's badge before mutation
select throws_ok(
    format($$select revoke_user_badge(%L::uuid, %L::uuid)$$, :'otherUserID', :'userBadgeID'),
    'awarded badge not found',
    'Should reject another user''s badge before mutation'
);

-- Should revoke the owned badge without notification
select lives_ok(
    format($$select revoke_user_badge(%L::uuid, %L::uuid)$$, :'userID', :'userBadgeID'),
    'Should revoke the owned badge without notification'
);

-- Should persist self-revocation without notification
select ok(
    exists (
        select 1 from user_badge
        where user_badge_id = :'userBadgeID'
        and is_listed = false
        and revocation_reason = 'recipient revoked badge'
        and revoked_at is not null
        and revoked_by_user_id = :'userID'
    )
    and not exists (select 1 from notification where user_id = :'userID' and kind = 'badge-revoked'),
    'Should persist self-revocation without notification'
);

-- Should record one recipient lifecycle audit row
select is(
    (select count(*)::integer from audit_log where action = 'badge_revoked_by_recipient' and actor_user_id = :'userID'),
    1,
    'Should record one recipient lifecycle audit row'
);

-- Should make repeated self-revocation a no-op
select lives_ok(
    format($$select revoke_user_badge(%L::uuid, %L::uuid)$$, :'userID', :'userBadgeID'),
    'Should make repeated self-revocation a no-op'
);

-- Should prevent revocation reversal
select throws_ok(
    format($$update user_badge set revoked_at = null where user_badge_id = %L$$, :'userBadgeID'),
    'badge revocation cannot be changed',
    'Should prevent revocation reversal'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
