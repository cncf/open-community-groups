-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actor1ID '00000000-0000-0000-0000-000000000011'
\set actor2ID '00000000-0000-0000-0000-000000000012'
\set audit1ID '00000000-0000-0000-0000-000000000101'
\set audit2ID '00000000-0000-0000-0000-000000000102'
\set audit3ID '00000000-0000-0000-0000-000000000103'
\set audit4ID '00000000-0000-0000-0000-000000000104'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set missingRegionID '00000000-0000-0000-0000-000000000041'
\set wildcardActorID '00000000-0000-0000-0000-000000000013'
\set wildcardAuditID '00000000-0000-0000-0000-000000000105'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'actor1ID', gen_random_bytes(32), 'alice@example.com', true, 'alice'),
    (:'actor2ID', gen_random_bytes(32), 'bob@example.com', true, 'bob'),
    (:'wildcardActorID', gen_random_bytes(32), 'userx1@example.com', true, 'userx1');

-- Communities
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values
    (
        :'community1ID',
        'https://e/community-1-mobile.png',
        'https://e/community-1.png',
        'Community 1',
        'Community One',
        'https://e/community-1-logo.png',
        'community-one'
    ),
    (
        :'community2ID',
        'https://e/community-2-mobile.png',
        'https://e/community-2.png',
        'Community 2',
        'Community Two',
        'https://e/community-2-logo.png',
        'community-two'
    );

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
        '[
            {
                "action": "community_updated",
                "actor_username": "userx1",
                "audit_log_id": "00000000-0000-0000-0000-000000000105",
                "created_at": 1707127200,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000001",
                "resource_name": "Community One",
                "resource_type": "community"
            },
            {
                "action": "region_added",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000103",
                "created_at": 1706954400,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000041",
                "resource_name": null,
                "resource_type": "region"
            },
            {
                "action": "group_added",
                "actor_username": "bob",
                "audit_log_id": "00000000-0000-0000-0000-000000000102",
                "created_at": 1706868000,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000031",
                "resource_name": "Platform",
                "resource_type": "group"
            },
            {
                "action": "community_updated",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000101",
                "created_at": 1706781600,
                "details": {"subject": "Roadmap updated"},
                "resource_id": "00000000-0000-0000-0000-000000000001",
                "resource_name": "Community One",
                "resource_type": "community"
            }
        ]'::jsonb,
        'total',
        4
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
        '[
            {
                "action": "community_updated",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000101",
                "created_at": 1706781600,
                "details": {"subject": "Roadmap updated"},
                "resource_id": "00000000-0000-0000-0000-000000000001",
                "resource_name": "Community One",
                "resource_type": "community"
            }
        ]'::jsonb,
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
        '[
            {
                "action": "community_updated",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000101",
                "created_at": 1706781600,
                "details": {"subject": "Roadmap updated"},
                "resource_id": "00000000-0000-0000-0000-000000000001",
                "resource_name": "Community One",
                "resource_type": "community"
            }
        ]'::jsonb,
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
