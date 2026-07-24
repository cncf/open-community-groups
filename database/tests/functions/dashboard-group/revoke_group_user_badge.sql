-- Tests permanent group badge revocation and recipient notification.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'b1100000-0000-0000-0000-000000000001'
\set communityID 'b1100000-0000-0000-0000-000000000002'
\set groupCategoryID 'b1100000-0000-0000-0000-000000000003'
\set groupID 'b1100000-0000-0000-0000-000000000004'
\set recipientID 'b1100000-0000-0000-0000-000000000005'
\set statusListID 'b1100000-0000-0000-0000-000000000006'
\set userBadgeID 'b1100000-0000-0000-0000-000000000007'
\set viewerID 'b1100000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Badge manager, recipient, and read-only viewer
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'actorID', 'hash', 'revoke-admin@example.test', true, 'revoke-admin'),
    (:'recipientID', 'hash', 'revoke-recipient@example.test', true, 'revoke-recipient'),
    (:'viewerID', 'hash', 'revoke-viewer@example.test', true, 'revoke-viewer');

-- Community that owns the award
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Revoke Community', '/logo', 'revoke-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the award
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Revoke Group', 'revoke-group');

-- Badge manager and viewer roles
insert into group_team (group_id, accepted, role, user_id)
values
    (:'groupID', true, 'admin', :'actorID'),
    (:'groupID', true, 'viewer', :'viewerID');

-- Status list containing the active award
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active award revoked by the test
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    user_id
) values (
    :'userBadgeID', :'statusListID', 0, :'groupID',
    '{"issuer":{"group_name":"Revoke Group"},"name":"Badge"}', 3, :'recipientID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should require a non-empty internal reason
select throws_ok(
    format($$select revoke_group_user_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, ' ')$$, :'actorID', :'communityID', :'groupID', :'userBadgeID'),
    'badge revocation reason is required',
    'Should require a non-empty internal reason'
);

-- Should reject a viewer before mutation
select throws_ok(
    format($$select revoke_group_user_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 'reason')$$, :'viewerID', :'communityID', :'groupID', :'userBadgeID'),
    '42501',
    'badge permission denied',
    'Should reject a viewer before mutation'
);

-- Should revoke the active award atomically
select lives_ok(
    format(
        $$select revoke_group_user_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '  policy violation  ')$$,
        :'actorID', :'communityID', :'groupID', :'userBadgeID'
    ),
    'Should revoke the active award atomically'
);

-- Should persist private audit state and clear profile listing
select ok(
    exists (
        select 1 from user_badge
        where user_badge_id = :'userBadgeID'
        and is_listed = false
        and revocation_reason = 'policy violation'
        and revoked_at is not null
        and revoked_by_user_id = :'actorID'
    )
    and exists (
        select 1 from audit_log
        where action = 'badge_revoked'
        and actor_user_id = :'actorID'
        and details->>'reason' = 'policy violation'
    ),
    'Should persist private audit state and clear profile listing'
);

-- Should notify the recipient without exposing the private reason
select ok(
    exists (
        select 1
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'badge-revoked'
        and n.user_id = :'recipientID'
        and ntd.data::text not ilike '%policy violation%'
    ),
    'Should notify the recipient without exposing the private reason'
);

-- Should make repeated revocation a no-op
select lives_ok(
    format($$select revoke_group_user_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 'another reason')$$, :'actorID', :'communityID', :'groupID', :'userBadgeID'),
    'Should make repeated revocation a no-op'
);

-- Should not duplicate notification, audit, or reason on replay
select ok(
    (select count(*) from notification where kind = 'badge-revoked') = 1
    and (select count(*) from audit_log where action = 'badge_revoked') = 1
    and (select revocation_reason from user_badge where user_badge_id = :'userBadgeID') = 'policy violation',
    'Should not duplicate notification, audit, or reason on replay'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
