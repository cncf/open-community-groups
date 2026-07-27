-- Tests refreshing the recipient identity binding for one active user badge.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set boundBadgeID 'b2060000-0000-0000-0000-000000000001'
\set boundSalt '0123456789abcdef0123456789abcdef'
\set communityID 'b2060000-0000-0000-0000-000000000002'
\set groupCategoryID 'b2060000-0000-0000-0000-000000000003'
\set groupID 'b2060000-0000-0000-0000-000000000004'
\set otherUserID 'b2060000-0000-0000-0000-000000000005'
\set revokedBadgeID 'b2060000-0000-0000-0000-000000000006'
\set staleBadgeID 'b2060000-0000-0000-0000-000000000007'
\set staleSalt 'fedcba9876543210fedcba9876543210'
\set statusListID 'b2060000-0000-0000-0000-000000000008'
\set unboundBadgeID 'b2060000-0000-0000-0000-000000000009'
\set userID 'b2060000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Badge owner and another dashboard user
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'otherUserID', 'hash', 'refresh-other@example.test', true, 'refresh-other'),
    (:'userID', 'hash', 'refresh-owner@example.test', true, 'refresh-owner');

-- Community that owns the issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Refresh Identity Community', '/logo', 'refresh-identity-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the badges
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Refresh Identity Group', 'refresh-identity-group');

-- Status list containing the awards
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active award already bound to the owner's current email
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    identity_bound_at, identity_hash, identity_salt, user_id
) values (
    :'boundBadgeID',
    '2026-03-01 00:00:00+00',
    :'statusListID',
    0,
    :'groupID',
    '{"name":"Badge"}',
    1,
    '2026-03-02 00:00:00+00',
    encode(digest('refresh-owner@example.test' || :'boundSalt', 'sha256'), 'hex'),
    :'boundSalt',
    :'userID'
);

-- Active award bound to an email the owner no longer uses
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    identity_bound_at, identity_hash, identity_salt, user_id
) values (
    :'staleBadgeID',
    '2026-03-01 00:00:00+00',
    :'statusListID',
    1,
    :'groupID',
    '{"name":"Badge"}',
    2,
    '2026-03-02 00:00:00+00',
    encode(digest('refresh-old@example.test' || :'staleSalt', 'sha256'), 'hex'),
    :'staleSalt',
    :'userID'
);

-- Active award without an identity binding
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    user_id
) values (
    :'unboundBadgeID',
    '2026-03-01 00:00:00+00',
    :'statusListID',
    2,
    :'groupID',
    '{"name":"Badge"}',
    3,
    :'userID'
);

-- Revoked award excluded from identity refreshes
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, is_listed, snapshot,
    status_list_index, revocation_reason, revoked_at, user_id
) values (
    :'revokedBadgeID',
    '2026-03-01 00:00:00+00',
    :'statusListID',
    3,
    :'groupID',
    false,
    '{"name":"Badge"}',
    4,
    'policy violation',
    '2026-03-03 00:00:00+00',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should bind a missing identity to the owner's current email
select ok(
    (
        select binding->>'identity_hash'
                = encode(digest('refresh-owner@example.test' || (binding->>'identity_salt'), 'sha256'), 'hex')
            and binding->>'identity_salt' ~ '^[0-9a-f]{32}$'
            and binding->>'identity_bound_at' is not null
        from refresh_user_badge_identity(:'userID', :'unboundBadgeID') binding
    ),
    'Should bind a missing identity to the owner''s current email'
);

-- Should persist the new binding on the previously unbound award
select ok(
    (
        select ub.identity_hash
                = encode(digest('refresh-owner@example.test' || ub.identity_salt, 'sha256'), 'hex')
            and ub.identity_salt ~ '^[0-9a-f]{32}$'
            and ub.identity_bound_at is not null
        from user_badge ub
        where ub.user_badge_id = :'unboundBadgeID'
    ),
    'Should persist the new binding on the previously unbound award'
);

-- Should keep an existing binding when the owner email still matches
select is(
    refresh_user_badge_identity(:'userID', :'boundBadgeID')::jsonb,
    jsonb_build_object(
        'identity_bound_at', '2026-03-02 00:00:00+00'::timestamptz,
        'identity_hash', encode(digest('refresh-owner@example.test' || :'boundSalt', 'sha256'), 'hex'),
        'identity_salt', :'boundSalt'
    ),
    'Should keep an existing binding when the owner email still matches'
);

-- Should rebind a stale identity to the owner's current email
select ok(
    (
        select binding->>'identity_hash'
                = encode(digest('refresh-owner@example.test' || (binding->>'identity_salt'), 'sha256'), 'hex')
            and binding->>'identity_salt' <> :'staleSalt'
            and (binding->>'identity_bound_at')::timestamptz > '2026-03-02 00:00:00+00'::timestamptz
        from refresh_user_badge_identity(:'userID', :'staleBadgeID') binding
    ),
    'Should rebind a stale identity to the owner''s current email'
);

-- Should reject a revoked badge
select throws_ok(
    format($$select refresh_user_badge_identity(%L::uuid, %L::uuid)$$, :'userID', :'revokedBadgeID'),
    'active user badge not found',
    'Should reject a revoked badge'
);

-- Should reject an unknown badge
select throws_ok(
    format($$select refresh_user_badge_identity(%L::uuid, %L::uuid)$$, :'userID', gen_random_uuid()),
    'active user badge not found',
    'Should reject an unknown badge'
);

-- Should reject another user's badge
select throws_ok(
    format($$select refresh_user_badge_identity(%L::uuid, %L::uuid)$$, :'otherUserID', :'boundBadgeID'),
    'active user badge not found',
    'Should reject another user''s badge'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
