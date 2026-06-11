-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actor1ID '3a1f0000-0000-0000-0000-000000000011'
\set actor2ID '3a1f0000-0000-0000-0000-000000000012'
\set audit1ID '3a1f0000-0000-0000-0000-000000000101'
\set audit2ID '3a1f0000-0000-0000-0000-000000000102'
\set audit3ID '3a1f0000-0000-0000-0000-000000000103'
\set audit4ID '3a1f0000-0000-0000-0000-000000000104'
\set audit5ID '3a1f0000-0000-0000-0000-000000000106'
\set audit6ID '3a1f0000-0000-0000-0000-000000000107'
\set audit7ID '3a1f0000-0000-0000-0000-000000000108'
\set audit8ID '3a1f0000-0000-0000-0000-000000000109'
\set audit9ID '3a1f0000-0000-0000-0000-000000000110'
\set audit10ID '3a1f0000-0000-0000-0000-000000000111'
\set audit11ID '3a1f0000-0000-0000-0000-000000000112'
\set communityID '3a1f0000-0000-0000-0000-000000000001'
\set groupCategoryID '3a1f0000-0000-0000-0000-000000000021'
\set groupID '3a1f0000-0000-0000-0000-000000000031'
\set otherGroupID '3a1f0000-0000-0000-0000-000000000032'
\set targetUserID '3a1f0000-0000-0000-0000-000000000041'
\set wildcardActorID '3a1f0000-0000-0000-0000-000000000013'
\set wildcardAuditID '3a1f0000-0000-0000-0000-000000000105'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, name, username)
values
    (:'actor1ID', gen_random_bytes(32), 'alice@example.com', true, 'Alice', 'alice'),
    (:'actor2ID', gen_random_bytes(32), 'bob@example.com', true, 'Bob', 'bob'),
    (:'wildcardActorID', gen_random_bytes(32), 'userx1@example.com', true, 'User X1', 'userx1'),
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
        :'audit5ID',
        'event_invitation_request_accepted',
        :'actor2ID',
        'bob',
        :'communityID',
        '2024-03-02 11:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000051"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit6ID',
        'event_invitation_request_rejected',
        :'actor1ID',
        'alice',
        :'communityID',
        '2024-03-02 12:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000052"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit7ID',
        'event_attendee_invitation_accepted',
        :'targetUserID',
        'sara',
        :'communityID',
        '2024-03-02 13:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000053"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit8ID',
        'event_attendee_invitation_rejected',
        :'targetUserID',
        'sara',
        :'communityID',
        '2024-03-02 14:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000054"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit9ID',
        'event_attendee_invitation_sent',
        :'actor2ID',
        'bob',
        :'communityID',
        '2024-03-02 15:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000055"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit10ID',
        'event_attendee_invitation_canceled',
        :'actor1ID',
        'alice',
        :'communityID',
        '2024-03-02 16:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000056"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit11ID',
        'event_attendee_attendance_canceled',
        :'actor1ID',
        'alice',
        :'communityID',
        '2024-03-02 16:30:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000057"}',
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
    ),
    (
        :'wildcardAuditID',
        'group_updated',
        :'wildcardActorID',
        'userx1',
        :'communityID',
        '2024-03-05 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'groupID',
        'group'
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
                "action": "group_updated",
                "actor_username": "userx1",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000105",
                "created_at": 1709632800,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000031",
                "resource_name": "Platform",
                "resource_type": "group"
            },
            {
                "action": "event_attendee_attendance_canceled",
                "actor_username": "alice",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000112",
                "created_at": 1709397000,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000057"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_attendee_invitation_canceled",
                "actor_username": "alice",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000111",
                "created_at": 1709395200,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000056"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_attendee_invitation_sent",
                "actor_username": "bob",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000110",
                "created_at": 1709391600,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000055"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_attendee_invitation_rejected",
                "actor_username": "sara",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000109",
                "created_at": 1709388000,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000054"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_attendee_invitation_accepted",
                "actor_username": "sara",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000108",
                "created_at": 1709384400,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000053"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_invitation_request_rejected",
                "actor_username": "alice",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000107",
                "created_at": 1709380800,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000052"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_invitation_request_accepted",
                "actor_username": "bob",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000106",
                "created_at": 1709377200,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000051"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "group_team_member_added",
                "actor_username": "bob",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000102",
                "created_at": 1709373600,
                "details": {"role": "admin"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "group_updated",
                "actor_username": "alice",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000101",
                "created_at": 1709287200,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000031",
                "resource_name": "Platform",
                "resource_type": "group"
            }
        ]'::jsonb,
        'total',
        10
    ),
    'Should return only group dashboard actions for the selected group'
);

-- Should filter group audit logs by actor and action
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
        '{"action": "event_invitation_request_accepted", "actor": "bo", "limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "event_invitation_request_accepted",
                "actor_username": "bob",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000106",
                "created_at": 1709377200,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000051"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            }
        ]'::jsonb,
        'total',
        1
    ),
    'Should filter group audit logs by actor and action'
);

-- Should filter group audit logs by attendee attendance cancellation action
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
        '{"action": "event_attendee_attendance_canceled", "limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "event_attendee_attendance_canceled",
                "actor_username": "alice",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000112",
                "created_at": 1709397000,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000057"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            }
        ]'::jsonb,
        'total',
        1
    ),
    'Should filter group audit logs by attendee attendance cancellation action'
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
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000102",
                "created_at": 1709373600,
                "details": {"role": "admin"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            }
        ]'::jsonb,
        'total',
        9
    ),
    'Should return group audit logs in ascending order with pagination'
);

-- Should treat actor filter metacharacters as literal text
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
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
