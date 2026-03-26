-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actor1ID '00000000-0000-0000-0000-000000000011'
\set actor2ID '00000000-0000-0000-0000-000000000012'
\set audit1ID '00000000-0000-0000-0000-000000000101'
\set audit2ID '00000000-0000-0000-0000-000000000102'
\set audit3ID '00000000-0000-0000-0000-000000000103'
\set audit4ID '00000000-0000-0000-0000-000000000104'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set otherGroupID '00000000-0000-0000-0000-000000000032'
\set targetUserID '00000000-0000-0000-0000-000000000041'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, name, username)
values
    (:'actor1ID', gen_random_bytes(32), 'alice@example.com', true, 'Alice', 'alice'),
    (:'actor2ID', gen_random_bytes(32), 'bob@example.com', true, 'Bob', 'bob'),
    (:'targetUserID', gen_random_bytes(32), 'sara@example.com', true, 'Sara', 'sara');

-- Community
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://e/community-mobile.png',
    'https://e/community.png',
    'Community 1',
    'Community One',
    'https://e/community-logo.png',
    'community-one'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Platform', 'platform'),
    (:'otherGroupID', :'communityID', :'groupCategoryID', 'Infra', 'infra');

-- Audit log rows
insert into audit_log (
    audit_log_id,
    action,
    actor_user_id,
    actor_username,
    community_id,
    created_at,
    details,
    group_id,
    resource_id,
    resource_type
) values
    (
        :'audit1ID',
        'group_updated',
        :'actor1ID',
        'alice',
        :'communityID',
        '2024-03-01 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'groupID',
        'group'
    ),
    (
        :'audit2ID',
        'group_team_member_added',
        :'actor2ID',
        'bob',
        :'communityID',
        '2024-03-02 10:00:00+00',
        '{"role": "admin"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit3ID',
        'event_added',
        :'actor1ID',
        'alice',
        :'communityID',
        '2024-03-03 10:00:00+00',
        '{}'::jsonb,
        :'otherGroupID',
        :'otherGroupID',
        'event'
    ),
    (
        :'audit4ID',
        'community_updated',
        :'actor1ID',
        'alice',
        :'communityID',
        '2024-03-04 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'communityID',
        'community'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only group dashboard actions for the selected group
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
        '{"limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "group_team_member_added",
                "actor_username": "bob",
                "audit_log_id": "00000000-0000-0000-0000-000000000102",
                "created_at": 1709373600,
                "details": {"role": "admin"},
                "resource_id": "00000000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "group_updated",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000101",
                "created_at": 1709287200,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000031",
                "resource_name": "Platform",
                "resource_type": "group"
            }
        ]'::jsonb,
        'total',
        2
    ),
    'Should return only group dashboard actions for the selected group'
);

-- Should filter group audit logs by actor and action
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
        '{"action": "group_team_member_added", "actor": "bo", "limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "group_team_member_added",
                "actor_username": "bob",
                "audit_log_id": "00000000-0000-0000-0000-000000000102",
                "created_at": 1709373600,
                "details": {"role": "admin"},
                "resource_id": "00000000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            }
        ]'::jsonb,
        'total',
        1
    ),
    'Should filter group audit logs by actor and action'
);

-- Should return group audit logs in ascending order with pagination
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
        '{"date_from": "2024-03-01", "date_to": "2024-03-02", "limit": 1, "offset": 1, "sort": "created-asc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "group_team_member_added",
                "actor_username": "bob",
                "audit_log_id": "00000000-0000-0000-0000-000000000102",
                "created_at": 1709373600,
                "details": {"role": "admin"},
                "resource_id": "00000000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            }
        ]'::jsonb,
        'total',
        2
    ),
    'Should return group audit logs in ascending order with pagination'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
