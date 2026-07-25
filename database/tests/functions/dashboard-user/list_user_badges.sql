-- Tests active dashboard user badge listings.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b2020000-0000-0000-0000-000000000001'
\set groupCategoryID 'b2020000-0000-0000-0000-000000000002'
\set groupID 'b2020000-0000-0000-0000-000000000003'
\set statusListID 'b2020000-0000-0000-0000-000000000004'
\set userBadgeFirstID 'b2020000-0000-0000-0000-000000000006'
\set userBadgeRevokedID 'b2020000-0000-0000-0000-000000000007'
\set userBadgeSecondID 'b2020000-0000-0000-0000-000000000008'
\set userID 'b2020000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User who owns active and revoked badge history
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'list-owner@example.test', true, 'list-owner');

-- Community that owns the issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'User List Community', '/logo', 'user-list-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the badges
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'User List Group', 'user-list-group');

-- Status list used by active and revoked awards
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active and revoked award rows
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    revocation_reason, revoked_at, user_id
) values
    (:'userBadgeSecondID', '2026-03-02 00:00:00+00', :'statusListID', 1, :'groupID', '{"name":"Second"}', 1, null, null, :'userID'),
    (:'userBadgeFirstID', '2026-03-01 00:00:00+00', :'statusListID', 0, :'groupID', '{"name":"First"}', 2, null, null, :'userID'),
    (:'userBadgeRevokedID', '2026-03-03 00:00:00+00', :'statusListID', 2, :'groupID', '{"name":"Revoked"}', 3, 'revoked', '2026-03-04 00:00:00+00', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list active awards only
select is(
    list_user_badges(:'userID')::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'awarded_at', '2026-03-01 00:00:00+00'::timestamptz,
            'badge_status_list_id', :'statusListID'::uuid,
            'display_order', 0,
            'group_id', :'groupID'::uuid,
            'is_listed', true,
            'snapshot', '{"name":"First"}'::jsonb,
            'status_list_index', 2,
            'user_badge_id', :'userBadgeFirstID'::uuid,

            'badge_id', null,
            'event_id', null,
            'event_name', null,
            'recipient_name', null,
            'recipient_username', null,
            'revocation_reason', null,
            'revoked_at', null,
            'revoked_by_user_id', null,
            'user_id', :'userID'::uuid
        ),
        jsonb_build_object(
            'awarded_at', '2026-03-02 00:00:00+00'::timestamptz,
            'badge_status_list_id', :'statusListID'::uuid,
            'display_order', 1,
            'group_id', :'groupID'::uuid,
            'is_listed', true,
            'snapshot', '{"name":"Second"}'::jsonb,
            'status_list_index', 1,
            'user_badge_id', :'userBadgeSecondID'::uuid,

            'badge_id', null,
            'event_id', null,
            'event_name', null,
            'recipient_name', null,
            'recipient_username', null,
            'revocation_reason', null,
            'revoked_at', null,
            'revoked_by_user_id', null,
            'user_id', :'userID'::uuid
        )
    ),
    'Should list active awards only'
);

-- Should respect the persisted display order
select is(
    (list_user_badges(:'userID')::jsonb)->0->'snapshot'->>'name',
    'First',
    'Should respect the persisted display order'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
