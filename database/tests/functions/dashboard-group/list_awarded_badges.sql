-- Tests searchable group badge award history.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set badgeID 'b1090000-0000-0000-0000-000000000001'
\set communityID 'b1090000-0000-0000-0000-000000000002'
\set eventCategoryID 'b1090000-0000-0000-0000-000000000008'
\set eventID 'b1090000-0000-0000-0000-000000000009'
\set groupCategoryID 'b1090000-0000-0000-0000-000000000003'
\set groupID 'b1090000-0000-0000-0000-000000000004'
\set recipientActiveID 'b1090000-0000-0000-0000-000000000005'
\set recipientRevokedID 'b1090000-0000-0000-0000-000000000006'
\set statusListID 'b1090000-0000-0000-0000-000000000007'
\set userBadgeActiveID 'b1090000-0000-0000-0000-000000000010'
\set userBadgeRevokedID 'b1090000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active and revoked recipients used by history filters
insert into "user" (user_id, auth_hash, email, email_verified, username, name)
values
    (:'recipientActiveID', 'hash', 'history-active@example.test', true, 'history-active', 'Active Recipient'),
    (:'recipientRevokedID', 'hash', 'history-revoked@example.test', true, 'history-revoked', 'Revoked Recipient');

-- Community that owns the history
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'History Community', '/logo', 'history-community');

-- Category used by the history source event
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Conference');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the history
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'History Group', 'history-group');

-- Event represented by one award source
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
values (:'eventID', 'Description', :'eventCategoryID', 'in-person', :'groupID', 'History Event', 'history-event', 'UTC');

-- Renamed badge definition represented by an older award snapshot
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Criteria', 'Description', :'groupID', 'history.png', 'Renamed History Badge');

-- Status list shared by the history rows
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active and revoked history rows
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, is_listed, snapshot, status_list_index,
    badge_id, event_id, revocation_reason, revoked_at, user_id
) values
    (
        :'userBadgeActiveID',
        '2026-02-02 00:00:00+00',
        :'statusListID',
        0,
        :'groupID',
        true,
        '{"name":"History Badge"}',
        1,
        :'badgeID',
        :'eventID',
        null,
        null,
        :'recipientActiveID'
    ),
    (
        :'userBadgeRevokedID',
        '2026-02-01 00:00:00+00',
        :'statusListID',
        0,
        :'groupID',
        true,
        '{"name":"History Badge"}',
        2,
        :'badgeID',
        null,
        'policy violation',
        '2026-02-03 00:00:00+00',
        :'recipientRevokedID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should filter active history
select is(
    list_awarded_badges(:'groupID', '{"status":"active"}')::jsonb,
    jsonb_build_object(
        'awards', jsonb_build_array(jsonb_build_object(
            'awarded_at', '2026-02-02 00:00:00+00'::timestamptz,
            'badge_status_list_id', :'statusListID'::uuid,
            'display_order', 0,
            'group_id', :'groupID'::uuid,
            'is_listed', true,
            'snapshot', '{"name":"History Badge"}'::jsonb,
            'status_list_index', 1,
            'user_badge_id', :'userBadgeActiveID'::uuid,

            'badge_id', :'badgeID'::uuid,
            'event_id', :'eventID'::uuid,
            'revocation_reason', null,
            'revoked_at', null,
            'revoked_by_user_id', null,
            'user_id', :'recipientActiveID'::uuid,

            'event_name', 'History Event',
            'recipient_name', 'Active Recipient',
            'recipient_username', 'history-active'
        )),
        'badges', jsonb_build_array(jsonb_build_object(
            'badge_id', :'badgeID'::uuid,
            'name', 'Renamed History Badge'
        )),
        'sources', jsonb_build_array(
            jsonb_build_object(
                'name', 'Group',
                'event_id', null
            ),
            jsonb_build_object(
                'name', 'History Event',
                'event_id', :'eventID'::uuid
            )
        ),
        'total', 1
    ),
    'Should filter active history'
);

-- Should filter revoked history
select is(
    list_awarded_badges(:'groupID', '{"status":"revoked"}')::jsonb,
    jsonb_build_object(
        'awards', jsonb_build_array(jsonb_build_object(
            'awarded_at', '2026-02-01 00:00:00+00'::timestamptz,
            'badge_status_list_id', :'statusListID'::uuid,
            'display_order', 0,
            'group_id', :'groupID'::uuid,
            'is_listed', true,
            'snapshot', '{"name":"History Badge"}'::jsonb,
            'status_list_index', 2,
            'user_badge_id', :'userBadgeRevokedID'::uuid,

            'badge_id', :'badgeID'::uuid,
            'event_id', null,
            'revocation_reason', 'policy violation',
            'revoked_at', '2026-02-03 00:00:00+00'::timestamptz,
            'revoked_by_user_id', null,
            'user_id', :'recipientRevokedID'::uuid,

            'event_name', null,
            'recipient_name', 'Revoked Recipient',
            'recipient_username', 'history-revoked'
        )),
        'badges', jsonb_build_array(jsonb_build_object(
            'badge_id', :'badgeID'::uuid,
            'name', 'Renamed History Badge'
        )),
        'sources', jsonb_build_array(
            jsonb_build_object(
                'name', 'Group',
                'event_id', null
            ),
            jsonb_build_object(
                'name', 'History Event',
                'event_id', :'eventID'::uuid
            )
        ),
        'total', 1
    ),
    'Should filter revoked history'
);

-- Should list active and revoked history
select is(
    list_awarded_badges(:'groupID', '{}')::jsonb,
    jsonb_build_object(
        'awards', jsonb_build_array(
            jsonb_build_object(
                'awarded_at', '2026-02-02 00:00:00+00'::timestamptz,
                'badge_status_list_id', :'statusListID'::uuid,
                'display_order', 0,
                'group_id', :'groupID'::uuid,
                'is_listed', true,
                'snapshot', '{"name":"History Badge"}'::jsonb,
                'status_list_index', 1,
                'user_badge_id', :'userBadgeActiveID'::uuid,

                'badge_id', :'badgeID'::uuid,
                'event_id', :'eventID'::uuid,
                'revocation_reason', null,
                'revoked_at', null,
                'revoked_by_user_id', null,
                'user_id', :'recipientActiveID'::uuid,

                'event_name', 'History Event',
                'recipient_name', 'Active Recipient',
                'recipient_username', 'history-active'
            ),
            jsonb_build_object(
                'awarded_at', '2026-02-01 00:00:00+00'::timestamptz,
                'badge_status_list_id', :'statusListID'::uuid,
                'display_order', 0,
                'group_id', :'groupID'::uuid,
                'is_listed', true,
                'snapshot', '{"name":"History Badge"}'::jsonb,
                'status_list_index', 2,
                'user_badge_id', :'userBadgeRevokedID'::uuid,

                'badge_id', :'badgeID'::uuid,
                'event_id', null,
                'revocation_reason', 'policy violation',
                'revoked_at', '2026-02-03 00:00:00+00'::timestamptz,
                'revoked_by_user_id', null,
                'user_id', :'recipientRevokedID'::uuid,

                'event_name', null,
                'recipient_name', 'Revoked Recipient',
                'recipient_username', 'history-revoked'
            )
        ),
        'badges', jsonb_build_array(jsonb_build_object(
            'badge_id', :'badgeID'::uuid,
            'name', 'Renamed History Badge'
        )),
        'sources', jsonb_build_array(
            jsonb_build_object(
                'name', 'Group',
                'event_id', null
            ),
            jsonb_build_object(
                'name', 'History Event',
                'event_id', :'eventID'::uuid
            )
        ),
        'total', 2
    ),
    'Should list active and revoked history'
);

-- Should return complete badge-filter options outside pagination
select is(
    list_awarded_badges(:'groupID', '{"limit":1}')::jsonb->'badges',
    jsonb_build_array(jsonb_build_object('badge_id', :'badgeID'::uuid, 'name', 'Renamed History Badge')),
    'Should return complete badge-filter options outside pagination'
);

-- Should return complete source options outside pagination
select is(
    list_awarded_badges(:'groupID', '{"limit":1}')::jsonb->'sources',
    jsonb_build_array(
        jsonb_build_object('name', 'Group', 'event_id', null),
        jsonb_build_object('name', 'History Event', 'event_id', :'eventID'::uuid)
    ),
    'Should return complete source options outside pagination'
);

-- Should filter history by event source
select is(
    list_awarded_badges(:'groupID', format('{"source":"%s"}', :'eventID')::jsonb)::jsonb->'total',
    '1'::jsonb,
    'Should filter history by event source'
);
select is(
    list_awarded_badges(:'groupID', format('{"source":"%s"}', :'eventID')::jsonb)::jsonb
        ->'awards'->0->>'user_badge_id',
    :'userBadgeActiveID',
    'Should return the event-sourced award for the event source filter'
);

-- Should filter direct group awards
select is(
    list_awarded_badges(:'groupID', '{"source":"group"}')::jsonb->'awards'->0->>'user_badge_id',
    :'userBadgeRevokedID',
    'Should filter direct group awards'
);

-- Should search recipient and badge names
select is(
    list_awarded_badges(:'groupID', '{"query":"Active Recipient"}')::jsonb,
    jsonb_build_object(
        'awards', jsonb_build_array(jsonb_build_object(
            'awarded_at', '2026-02-02 00:00:00+00'::timestamptz,
            'badge_status_list_id', :'statusListID'::uuid,
            'display_order', 0,
            'group_id', :'groupID'::uuid,
            'is_listed', true,
            'snapshot', '{"name":"History Badge"}'::jsonb,
            'status_list_index', 1,
            'user_badge_id', :'userBadgeActiveID'::uuid,

            'badge_id', :'badgeID'::uuid,
            'event_id', :'eventID'::uuid,
            'revocation_reason', null,
            'revoked_at', null,
            'revoked_by_user_id', null,
            'user_id', :'recipientActiveID'::uuid,

            'event_name', 'History Event',
            'recipient_name', 'Active Recipient',
            'recipient_username', 'history-active'
        )),
        'badges', jsonb_build_array(jsonb_build_object(
            'badge_id', :'badgeID'::uuid,
            'name', 'Renamed History Badge'
        )),
        'sources', jsonb_build_array(
            jsonb_build_object(
                'name', 'Group',
                'event_id', null
            ),
            jsonb_build_object(
                'name', 'History Event',
                'event_id', :'eventID'::uuid
            )
        ),
        'total', 1
    ),
    'Should search recipient and badge names'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
