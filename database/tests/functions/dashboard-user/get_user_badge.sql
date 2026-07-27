-- Tests reading one active dashboard user badge.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set boundBadgeID 'b2010000-0000-0000-0000-000000000008'
\set boundSalt '0123456789abcdef0123456789abcdef'
\set communityID 'b2010000-0000-0000-0000-000000000001'
\set groupCategoryID 'b2010000-0000-0000-0000-000000000002'
\set groupID 'b2010000-0000-0000-0000-000000000003'
\set otherUserID 'b2010000-0000-0000-0000-000000000004'
\set statusListID 'b2010000-0000-0000-0000-000000000005'
\set userBadgeID 'b2010000-0000-0000-0000-000000000006'
\set userID 'b2010000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Badge owner and another dashboard user
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'otherUserID', 'hash', 'get-other@example.test', true, 'get-other'),
    (:'userID', 'hash', 'get-owner@example.test', true, 'get-owner');

-- Community that owns the issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Get Badge Community', '/logo', 'get-badge-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the badge
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Get Badge Group', 'get-badge-group');

-- Status list containing the active award
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active award owned by the dashboard user
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    user_id
) values (
    :'userBadgeID',
    '2026-03-01 00:00:00+00',
    :'statusListID',
    0,
    :'groupID',
    '{"name":"Badge"}',
    1,
    :'userID'
);

-- Active award bound to the owner's email
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    identity_bound_at, identity_hash, identity_salt, user_id
) values (
    :'boundBadgeID',
    '2026-03-01 00:00:00+00',
    :'statusListID',
    1,
    :'groupID',
    '{"name":"Badge"}',
    2,
    '2026-03-02 00:00:00+00',
    encode(digest('get-owner@example.test' || :'boundSalt', 'sha256'), 'hex'),
    :'boundSalt',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return an active badge owned by the user
select is(
    get_user_badge(:'userID', :'userBadgeID')::jsonb,
    jsonb_build_object(
        'awarded_at', '2026-03-01 00:00:00+00'::timestamptz,
        'badge_status_list_id', :'statusListID'::uuid,
        'display_order', 0,
        'group_id', :'groupID'::uuid,
        'is_listed', true,
        'snapshot', '{"name":"Badge"}'::jsonb,
        'status_list_index', 1,
        'user_badge_id', :'userBadgeID'::uuid,

        'badge_id', null,
        'event_id', null,
        'event_name', null,
        'identity_bound_at', null,
        'identity_hash', null,
        'identity_salt', null,
        'recipient_name', null,
        'recipient_username', null,
        'revocation_reason', null,
        'revoked_at', null,
        'revoked_by_user_id', null,
        'user_id', :'userID'::uuid
    ),
    'Should return an active badge owned by the user'
);

-- Should not return another user's badge
select is(get_user_badge(:'otherUserID', :'userBadgeID')::jsonb, null::jsonb, 'Should not return another user''s badge');

-- Should not return an unknown badge
select is(get_user_badge(:'userID', gen_random_uuid())::jsonb, null::jsonb, 'Should not return an unknown badge');

-- Should return the persisted identity binding fields
select ok(
    get_user_badge(:'userID', :'boundBadgeID')::jsonb @> jsonb_build_object(
        'identity_bound_at', '2026-03-02 00:00:00+00'::timestamptz,
        'identity_hash', encode(digest('get-owner@example.test' || :'boundSalt', 'sha256'), 'hex'),
        'identity_salt', :'boundSalt'
    ),
    'Should return the persisted identity binding fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
