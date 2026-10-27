-- Tests projecting badge award rows into the base UserBadge JSON.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set badgeID 'e6b60000-0000-0000-0000-000000000001'
\set boundAwardID 'e6b60000-0000-0000-0000-000000000002'
\set boundHash 'abababababababababababababababababababababababababababababababab'
\set boundSalt 'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd'
\set communityID 'e6b60000-0000-0000-0000-000000000003'
\set eventCategoryID 'e6b60000-0000-0000-0000-000000000004'
\set eventID 'e6b60000-0000-0000-0000-000000000005'
\set groupCategoryID 'e6b60000-0000-0000-0000-000000000006'
\set groupID 'e6b60000-0000-0000-0000-000000000007'
\set recipientUserID 'e6b60000-0000-0000-0000-000000000008'
\set revokedAwardID 'e6b60000-0000-0000-0000-000000000009'
\set revokerUserID 'e6b60000-0000-0000-0000-00000000000a'
\set statusListID 'e6b60000-0000-0000-0000-00000000000b'
\set unboundAwardID 'e6b60000-0000-0000-0000-00000000000c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community issuing the awards
select fx_community(:'communityID');

-- Badge recipient
select fx_user(:'recipientUserID');

-- Organizer who revoked an award
select fx_user(:'revokerUserID');

-- Event category used by the award source event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the issuing group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Issuing group
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Badge definition retained by the bound award
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (
    :'badgeID',
    'Attend the event',
    'User badge JSON badge',
    :'groupID',
    'user-badge-json.png',
    'User Badge JSON'
);

-- Status list containing every award
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Event the bound award was issued for
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Active award bound to the recipient email, issued for the event
insert into user_badge (
    user_badge_id,
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,

    badge_id,
    event_id,
    identity_bound_at,
    identity_hash,
    identity_salt,
    user_id
) values (
    :'boundAwardID',
    '2026-03-01 00:00:00+00',
    :'statusListID',
    0,
    :'groupID',
    false,
    '{"name":"Bound"}',
    1,

    :'badgeID',
    :'eventID',
    '2026-03-02 00:00:00+00',
    :'boundHash',
    :'boundSalt',
    :'recipientUserID'
);

-- Revoked group award without an identity binding
insert into user_badge (
    user_badge_id,
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,

    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    :'revokedAwardID',
    '2026-03-03 00:00:00+00',
    :'statusListID',
    2,
    :'groupID',
    false,
    '{"name":"Revoked"}',
    3,

    'Issued by mistake',
    '2026-03-04 00:00:00+00',
    :'revokerUserID',
    :'recipientUserID'
);

-- Active group award without an identity binding
insert into user_badge (
    user_badge_id,
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,

    user_id
) values (
    :'unboundAwardID',
    '2026-03-05 00:00:00+00',
    :'statusListID',
    1,
    :'groupID',
    true,
    '{"name":"Unbound"}',
    2,

    :'recipientUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include explicit null identity keys for an unbound award when requested
select is(
    (select user_badge_json(ub, true) from user_badge ub where ub.user_badge_id = :'unboundAwardID'),
    jsonb_build_object(
        'awarded_at', '2026-03-05 00:00:00+00'::timestamptz,
        'badge_status_list_id', :'statusListID'::uuid,
        'display_order', 1,
        'group_id', :'groupID'::uuid,
        'is_listed', true,
        'snapshot', '{"name":"Unbound"}'::jsonb,
        'status_list_index', 2,
        'user_badge_id', :'unboundAwardID'::uuid,

        'badge_id', null,
        'event_id', null,
        'identity_bound_at', null,
        'identity_hash', null,
        'identity_salt', null,
        'revocation_reason', null,
        'revoked_at', null,
        'revoked_by_user_id', null,
        'user_id', :'recipientUserID'::uuid
    ),
    'Should include explicit null identity keys for an unbound award when requested'
);

-- Should include the identity binding of a bound award when requested
select is(
    (select user_badge_json(ub, true) from user_badge ub where ub.user_badge_id = :'boundAwardID'),
    jsonb_build_object(
        'awarded_at', '2026-03-01 00:00:00+00'::timestamptz,
        'badge_status_list_id', :'statusListID'::uuid,
        'display_order', 0,
        'group_id', :'groupID'::uuid,
        'is_listed', false,
        'snapshot', '{"name":"Bound"}'::jsonb,
        'status_list_index', 1,
        'user_badge_id', :'boundAwardID'::uuid,

        'badge_id', :'badgeID'::uuid,
        'event_id', :'eventID'::uuid,
        'identity_bound_at', '2026-03-02 00:00:00+00'::timestamptz,
        'identity_hash', :'boundHash',
        'identity_salt', :'boundSalt',
        'revocation_reason', null,
        'revoked_at', null,
        'revoked_by_user_id', null,
        'user_id', :'recipientUserID'::uuid
    ),
    'Should include the identity binding of a bound award when requested'
);

-- Should omit the identity keys when not requested
select is(
    (select user_badge_json(ub, false) from user_badge ub where ub.user_badge_id = :'boundAwardID'),
    jsonb_build_object(
        'awarded_at', '2026-03-01 00:00:00+00'::timestamptz,
        'badge_status_list_id', :'statusListID'::uuid,
        'display_order', 0,
        'group_id', :'groupID'::uuid,
        'is_listed', false,
        'snapshot', '{"name":"Bound"}'::jsonb,
        'status_list_index', 1,
        'user_badge_id', :'boundAwardID'::uuid,

        'badge_id', :'badgeID'::uuid,
        'event_id', :'eventID'::uuid,
        'revocation_reason', null,
        'revoked_at', null,
        'revoked_by_user_id', null,
        'user_id', :'recipientUserID'::uuid
    ),
    'Should omit the identity keys when not requested'
);

-- Should project the revocation fields of a revoked award
select is(
    (select user_badge_json(ub, false) from user_badge ub where ub.user_badge_id = :'revokedAwardID'),
    jsonb_build_object(
        'awarded_at', '2026-03-03 00:00:00+00'::timestamptz,
        'badge_status_list_id', :'statusListID'::uuid,
        'display_order', 2,
        'group_id', :'groupID'::uuid,
        'is_listed', false,
        'snapshot', '{"name":"Revoked"}'::jsonb,
        'status_list_index', 3,
        'user_badge_id', :'revokedAwardID'::uuid,

        'badge_id', null,
        'event_id', null,
        'revocation_reason', 'Issued by mistake',
        'revoked_at', '2026-03-04 00:00:00+00'::timestamptz,
        'revoked_by_user_id', :'revokerUserID'::uuid,
        'user_id', :'recipientUserID'::uuid
    ),
    'Should project the revocation fields of a revoked award'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
