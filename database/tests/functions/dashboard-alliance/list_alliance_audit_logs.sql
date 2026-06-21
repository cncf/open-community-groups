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
\set audit5ID '00000000-0000-0000-0000-000000000106'
\set audit6ID '00000000-0000-0000-0000-000000000107'
\set audit7ID '00000000-0000-0000-0000-000000000108'
\set alliance1ID '00000000-0000-0000-0000-000000000001'
\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set deletedRegionID '00000000-0000-0000-0000-000000000042'
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

-- Alliances
insert into alliance (
    alliance_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values
    (
        :'alliance1ID',
        'https://e/alliance-1-mobile.png',
        'https://e/alliance-1.png',
        'Alliance 1',
        'Alliance One',
        'https://e/alliance-1-logo.png',
        'alliance-one'
    ),
    (
        :'alliance2ID',
        'https://e/alliance-2-mobile.png',
        'https://e/alliance-2.png',
        'Alliance 2',
        'Alliance Two',
        'https://e/alliance-2-logo.png',
        'alliance-two'
    );

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'alliance1ID', 'Technology');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'alliance1ID', :'groupCategoryID', 'Platform', 'platform');

-- Audit log rows
insert into audit_log (
    audit_log_id,
    action,
    actor_user_id,
    actor_username,
    alliance_id,
    created_at,
    details,
    resource_id,
    resource_type
) values
    (
        :'audit1ID',
        'alliance_updated',
        :'actor1ID',
        'alice',
        :'alliance1ID',
        '2024-02-01 10:00:00+00',
        '{"subject": "Roadmap updated"}',
        :'alliance1ID',
        'alliance'
    ),
    (
        :'audit2ID',
        'group_added',
        :'actor2ID',
        'bob',
        :'alliance1ID',
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
        :'alliance1ID',
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
        :'alliance2ID',
        '2024-02-04 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        'event'
    ),
    (
        :'wildcardAuditID',
        'alliance_updated',
        :'wildcardActorID',
        'userx1',
        :'alliance1ID',
        '2024-02-05 10:00:00+00',
        '{}'::jsonb,
        :'alliance1ID',
        'alliance'
    ),
    (
        :'audit5ID',
        'alliance_team_invitation_accepted',
        :'actor1ID',
        'alice',
        :'alliance1ID',
        '2024-02-06 10:00:00+00',
        '{}'::jsonb,
        :'actor1ID',
        'user'
    ),
    (
        :'audit6ID',
        'alliance_team_invitation_rejected',
        :'actor2ID',
        'bob',
        :'alliance1ID',
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
        :'alliance1ID',
        '2024-02-07 10:00:00+00',
        '{"name": "Atlantis"}'::jsonb,
        :'deletedRegionID',
        'region'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only alliance dashboard actions for the selected alliance
select is(
    list_alliance_audit_logs(
        :'alliance1ID'::uuid,
        '{"limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "region_deleted",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000108",
                "created_at": 1707300000,
                "details": {"name": "Atlantis"},
                "resource_id": "00000000-0000-0000-0000-000000000042",
                "resource_name": "Atlantis",
                "resource_type": "region"
            },
            {
                "action": "alliance_team_invitation_rejected",
                "actor_username": "bob",
                "audit_log_id": "00000000-0000-0000-0000-000000000107",
                "created_at": 1707296400,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000012",
                "resource_name": "bob",
                "resource_type": "user"
            },
            {
                "action": "alliance_team_invitation_accepted",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000106",
                "created_at": 1707213600,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000011",
                "resource_name": "alice",
                "resource_type": "user"
            },
            {
                "action": "alliance_updated",
                "actor_username": "userx1",
                "audit_log_id": "00000000-0000-0000-0000-000000000105",
                "created_at": 1707127200,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000001",
                "resource_name": "Alliance One",
                "resource_type": "alliance"
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
                "action": "alliance_updated",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000101",
                "created_at": 1706781600,
                "details": {"subject": "Roadmap updated"},
                "resource_id": "00000000-0000-0000-0000-000000000001",
                "resource_name": "Alliance One",
                "resource_type": "alliance"
            }
        ]'::jsonb,
        'total',
        7
    ),
    'Should return only alliance dashboard actions for the selected alliance'
);

-- Should filter alliance audit logs by action and actor
select is(
    list_alliance_audit_logs(
        :'alliance1ID'::uuid,
        '{"action": "alliance_updated", "actor": "ali", "limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "alliance_updated",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000101",
                "created_at": 1706781600,
                "details": {"subject": "Roadmap updated"},
                "resource_id": "00000000-0000-0000-0000-000000000001",
                "resource_name": "Alliance One",
                "resource_type": "alliance"
            }
        ]'::jsonb,
        'total',
        1
    ),
    'Should filter alliance audit logs by action and actor'
);

-- Should return alliance audit logs in ascending order with pagination
select is(
    list_alliance_audit_logs(
        :'alliance1ID'::uuid,
        '{"date_from": "2024-02-01", "date_to": "2024-02-02", "limit": 1, "offset": 0, "sort": "created-asc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "alliance_updated",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000101",
                "created_at": 1706781600,
                "details": {"subject": "Roadmap updated"},
                "resource_id": "00000000-0000-0000-0000-000000000001",
                "resource_name": "Alliance One",
                "resource_type": "alliance"
            }
        ]'::jsonb,
        'total',
        2
    ),
    'Should return alliance audit logs in ascending order with pagination'
);

-- Should treat actor filter metacharacters as literal text
select is(
    list_alliance_audit_logs(
        :'alliance1ID'::uuid,
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
