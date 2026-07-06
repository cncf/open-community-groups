-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actor1ID '2c0e0000-0000-0000-0000-000000000001'
\set actor2ID '2c0e0000-0000-0000-0000-000000000002'
\set audit1ID '2c0e0000-0000-0000-0000-000000000003'
\set audit2ID '2c0e0000-0000-0000-0000-000000000004'
\set audit3ID '2c0e0000-0000-0000-0000-000000000005'
\set audit4ID '2c0e0000-0000-0000-0000-000000000006'
\set audit5ID '2c0e0000-0000-0000-0000-000000000007'
\set audit6ID '2c0e0000-0000-0000-0000-000000000008'
\set audit7ID '2c0e0000-0000-0000-0000-000000000009'
\set community1ID '2c0e0000-0000-0000-0000-000000000010'
\set community2ID '2c0e0000-0000-0000-0000-000000000011'
\set deletedRegionID '2c0e0000-0000-0000-0000-000000000012'
\set groupCategoryID '2c0e0000-0000-0000-0000-000000000013'
\set groupID '2c0e0000-0000-0000-0000-000000000014'
\set missingRegionID '2c0e0000-0000-0000-0000-000000000015'
\set wildcardActorID '2c0e0000-0000-0000-0000-000000000016'
\set wildcardAuditID '2c0e0000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'community1ID',
    'community-one',
    'Community One',
    'Community 1',
    'https://example.com/community-1-mobile.png',
    'https://example.com/community-1.png',
    'https://example.com/community-1-logo.png'
), (
    :'community2ID',
    'community-two',
    'Community Two',
    'Community 2',
    'https://example.com/community-2-mobile.png',
    'https://example.com/community-2.png',
    'https://example.com/community-2-logo.png'
);

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'actor1ID', gen_random_bytes(32), 'alice@example.com', true, 'alice'),
    (:'actor2ID', gen_random_bytes(32), 'bob@example.com', true, 'bob'),
    (:'wildcardActorID', gen_random_bytes(32), 'userx1@example.com', true, 'userx1');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'community1ID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'community1ID', :'groupCategoryID', 'Platform', 'platform');

-- Audit log rows
insert into audit_log (
    audit_log_id,
    action,
    actor_user_id,
    actor_username,
    community_id,
    created_at,
    details,
    resource_id,
    resource_type
) values
    (
        :'audit1ID',
        'community_updated',
        :'actor1ID',
        'alice',
        :'community1ID',
        '2024-02-01 10:00:00+00',
        '{"subject": "Roadmap updated"}',
        :'community1ID',
        'community'
    ),
    (
        :'audit2ID',
        'group_added',
        :'actor2ID',
        'bob',
        :'community1ID',
        '2024-02-02 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        'group'
    ),
    (
        :'audit3ID',
        'region_added',
        :'actor1ID',
        'alice',
        :'community1ID',
        '2024-02-03 10:00:00+00',
        '{}'::jsonb,
        :'missingRegionID',
        'region'
    ),
    (
        :'audit4ID',
        'event_added',
        :'actor1ID',
        'alice',
        :'community2ID',
        '2024-02-04 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        'event'
    ),
    (
        :'wildcardAuditID',
        'community_updated',
        :'wildcardActorID',
        'userx1',
        :'community1ID',
        '2024-02-05 10:00:00+00',
        '{}'::jsonb,
        :'community1ID',
        'community'
    ),
    (
        :'audit5ID',
        'community_team_invitation_accepted',
        :'actor1ID',
        'alice',
        :'community1ID',
        '2024-02-06 10:00:00+00',
        '{}'::jsonb,
        :'actor1ID',
        'user'
    ),
    (
        :'audit6ID',
        'community_team_invitation_rejected',
        :'actor2ID',
        'bob',
        :'community1ID',
        '2024-02-07 09:00:00+00',
        '{}'::jsonb,
        :'actor2ID',
        'user'
    ),
    (
        :'audit7ID',
        'region_deleted',
        :'actor1ID',
        'alice',
        :'community1ID',
        '2024-02-07 10:00:00+00',
        '{"name": "Atlantis"}'::jsonb,
        :'deletedRegionID',
        'region'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only community dashboard actions for the selected community
select is(
    list_community_audit_logs(
        :'community1ID'::uuid,
        '{"limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        format(
            $json$
        [
            {
                "action": "region_deleted",
                "actor_username": "alice",
                "audit_log_id": "%s",
                "created_at": 1707300000,
                "details": {"name": "Atlantis"},
                "resource_id": "%s",
                "resource_name": "Atlantis",
                "resource_type": "region"
            },
            {
                "action": "community_team_invitation_rejected",
                "actor_username": "bob",
                "audit_log_id": "%s",
                "created_at": 1707296400,
                "details": {},
                "resource_id": "%s",
                "resource_name": "bob",
                "resource_type": "user"
            },
            {
                "action": "community_team_invitation_accepted",
                "actor_username": "alice",
                "audit_log_id": "%s",
                "created_at": 1707213600,
                "details": {},
                "resource_id": "%s",
                "resource_name": "alice",
                "resource_type": "user"
            },
            {
                "action": "community_updated",
                "actor_username": "userx1",
                "audit_log_id": "%s",
                "created_at": 1707127200,
                "details": {},
                "resource_id": "%s",
                "resource_name": "Community One",
                "resource_type": "community"
            },
            {
                "action": "region_added",
                "actor_username": "alice",
                "audit_log_id": "%s",
                "created_at": 1706954400,
                "details": {},
                "resource_id": "%s",
                "resource_name": null,
                "resource_type": "region"
            },
            {
                "action": "group_added",
                "actor_username": "bob",
                "audit_log_id": "%s",
                "created_at": 1706868000,
                "details": {},
                "resource_id": "%s",
                "resource_name": "Platform",
                "resource_type": "group"
            },
            {
                "action": "community_updated",
                "actor_username": "alice",
                "audit_log_id": "%s",
                "created_at": 1706781600,
                "details": {"subject": "Roadmap updated"},
                "resource_id": "%s",
                "resource_name": "Community One",
                "resource_type": "community"
            }
        ]
            $json$,
            :'audit7ID',
            :'deletedRegionID',
            :'audit6ID',
            :'actor2ID',
            :'audit5ID',
            :'actor1ID',
            :'wildcardAuditID',
            :'community1ID',
            :'audit3ID',
            :'missingRegionID',
            :'audit2ID',
            :'groupID',
            :'audit1ID',
            :'community1ID'
        )::jsonb,
        'total',
        7
    ),
    'Should return only community dashboard actions for the selected community'
);

-- Should filter community audit logs by action and actor
select is(
    list_community_audit_logs(
        :'community1ID'::uuid,
        '{"action": "community_updated", "actor": "ali", "limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        format(
            $json$
        [
            {
                "action": "community_updated",
                "actor_username": "alice",
                "audit_log_id": "%s",
                "created_at": 1706781600,
                "details": {"subject": "Roadmap updated"},
                "resource_id": "%s",
                "resource_name": "Community One",
                "resource_type": "community"
            }
        ]
            $json$,
            :'audit1ID',
            :'community1ID'
        )::jsonb,
        'total',
        1
    ),
    'Should filter community audit logs by action and actor'
);

-- Should return community audit logs in ascending order with pagination
select is(
    list_community_audit_logs(
        :'community1ID'::uuid,
        '{"date_from": "2024-02-01", "date_to": "2024-02-02", "limit": 1, "offset": 0, "sort": "created-asc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        format(
            $json$
        [
            {
                "action": "community_updated",
                "actor_username": "alice",
                "audit_log_id": "%s",
                "created_at": 1706781600,
                "details": {"subject": "Roadmap updated"},
                "resource_id": "%s",
                "resource_name": "Community One",
                "resource_type": "community"
            }
        ]
            $json$,
            :'audit1ID',
            :'community1ID'
        )::jsonb,
        'total',
        2
    ),
    'Should return community audit logs in ascending order with pagination'
);

-- Should treat actor filter metacharacters as literal text
select is(
    list_community_audit_logs(
        :'community1ID'::uuid,
        '{"actor": "user_1", "limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[]'::jsonb,
        'total',
        0
    ),
    'Should treat actor filter metacharacters as literal text'
);

-- Should default unsupported sort values to created descending
select is(
    list_community_audit_logs(
        :'community1ID'::uuid,
        '{"limit": 1, "offset": 0, "sort": "resource-asc"}'::jsonb
    )::jsonb#>>'{logs,0,action}',
    'region_deleted',
    'Should default unsupported community audit sort values to created descending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
