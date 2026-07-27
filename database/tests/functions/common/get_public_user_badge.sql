-- Tests public badge credential record reads.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set boundBadgeID 'b0030000-0000-0000-0000-000000000007'
\set boundSalt '0123456789abcdef0123456789abcdef'
\set communityID 'b0030000-0000-0000-0000-000000000001'
\set groupCategoryID 'b0030000-0000-0000-0000-000000000002'
\set groupID 'b0030000-0000-0000-0000-000000000003'
\set statusListID 'b0030000-0000-0000-0000-000000000004'
\set userBadgeID 'b0030000-0000-0000-0000-000000000005'
\set userID 'b0030000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Current recipient associated with the opaque credential
insert into "user" (user_id, auth_hash, email, email_verified, username, name)
values (:'userID', 'hash', 'recipient@example.test', true, 'recipient', 'Recipient');

-- Community that issued the credential
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Public Community', '/logo', 'public-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the credential
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Public Group', 'public-group');

-- Status list referenced by the credential
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Durable credential record
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    user_id
) values (
    :'userBadgeID',
    '2026-01-02 03:04:05+00',
    :'statusListID',
    0,
    :'groupID',
    '{"name":"Badge"}',
    9,
    :'userID'
);

-- Durable credential record bound to the recipient email
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    identity_bound_at, identity_hash, identity_salt, user_id
) values (
    :'boundBadgeID',
    '2026-01-02 03:04:05+00',
    :'statusListID',
    1,
    :'groupID',
    '{"name":"Badge"}',
    10,
    '2026-03-02 00:00:00+00',
    encode(digest('recipient@example.test' || :'boundSalt', 'sha256'), 'hex'),
    :'boundSalt',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return durable and current recipient fields
select is(
    get_public_user_badge(:'userBadgeID')::jsonb,
    jsonb_build_object(
        'awarded_at', '2026-01-02 03:04:05+00'::timestamptz,
        'badge_status_list_id', :'statusListID'::uuid,
        'display_order', 0,
        'group_id', :'groupID'::uuid,
        'is_listed', true,
        'snapshot', '{"name":"Badge"}'::jsonb,
        'status_list_index', 9,
        'user_badge_id', :'userBadgeID'::uuid,

        'badge_id', null,
        'event_id', null,
        'identity_bound_at', null,
        'identity_hash', null,
        'identity_salt', null,
        'revocation_reason', null,
        'revoked_at', null,
        'revoked_by_user_id', null,
        'user_id', :'userID'::uuid,

        'recipient_name', 'Recipient',
        'recipient_username', 'recipient'
    ),
    'Should return durable and current recipient fields'
);

-- Should return null for an unknown credential
select is(get_public_user_badge(gen_random_uuid())::jsonb, null::jsonb, 'Should return null for an unknown credential');

-- Should return the persisted identity binding fields
select ok(
    get_public_user_badge(:'boundBadgeID')::jsonb @> jsonb_build_object(
        'identity_bound_at', '2026-03-02 00:00:00+00'::timestamptz,
        'identity_hash', encode(digest('recipient@example.test' || :'boundSalt', 'sha256'), 'hex'),
        'identity_salt', :'boundSalt'
    ),
    'Should return the persisted identity binding fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
