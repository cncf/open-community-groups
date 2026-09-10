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

-- Baseline community, group categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'otherUserID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

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
    'OCG01',
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
