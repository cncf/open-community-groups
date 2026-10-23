-- Tests the community dashboard audit log action allow-list and scope.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '2c0e0000-0000-0000-0000-000000000010'
\set community2ID '2c0e0000-0000-0000-0000-000000000011'
\set otherCommunityAuditID '2c0e0000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose audit log is listed
select fx_community(:'community1ID');

-- Other community whose audit rows must be excluded
select fx_community(:'community2ID');

-- Audit rows for every community dashboard action plus a hidden action
insert into audit_log (action, resource_id, resource_type, community_id) values
    ('community_custom_notification_sent', :'community1ID', 'community', :'community1ID'),
    ('community_team_invitation_accepted', :'community1ID', 'community', :'community1ID'),
    ('community_team_invitation_rejected', :'community1ID', 'community', :'community1ID'),
    ('community_team_member_added', :'community1ID', 'community', :'community1ID'),
    ('community_team_member_removed', :'community1ID', 'community', :'community1ID'),
    ('community_team_member_role_updated', :'community1ID', 'community', :'community1ID'),
    ('community_updated', :'community1ID', 'community', :'community1ID'),
    ('event_added', :'community1ID', 'community', :'community1ID'),
    ('event_category_added', :'community1ID', 'community', :'community1ID'),
    ('event_category_deleted', :'community1ID', 'community', :'community1ID'),
    ('event_category_updated', :'community1ID', 'community', :'community1ID'),
    ('group_activated', :'community1ID', 'community', :'community1ID'),
    ('group_added', :'community1ID', 'community', :'community1ID'),
    ('group_category_added', :'community1ID', 'community', :'community1ID'),
    ('group_category_deleted', :'community1ID', 'community', :'community1ID'),
    ('group_category_updated', :'community1ID', 'community', :'community1ID'),
    ('group_deactivated', :'community1ID', 'community', :'community1ID'),
    ('group_deleted', :'community1ID', 'community', :'community1ID'),
    ('group_external_payments_updated', :'community1ID', 'community', :'community1ID'),
    ('group_payment_recipient_updated', :'community1ID', 'community', :'community1ID'),
    ('group_updated', :'community1ID', 'community', :'community1ID'),
    ('region_added', :'community1ID', 'community', :'community1ID'),
    ('region_deleted', :'community1ID', 'community', :'community1ID'),
    ('region_updated', :'community1ID', 'community', :'community1ID');

-- Audit row of a community dashboard action in the other community
insert into audit_log (audit_log_id, action, resource_id, resource_type, community_id)
values (:'otherCommunityAuditID', 'community_updated', :'community2ID', 'community', :'community2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list every community dashboard action and skip hidden actions
select is(
    (
        select jsonb_agg(log_item->>'action' order by log_item->>'action' collate "C")
        from jsonb_array_elements(
            list_community_audit_logs(:'community1ID'::uuid, '{"limit": 100}'::jsonb)::jsonb->'logs'
        ) log_item
    ),
    '[
        "community_custom_notification_sent",
        "community_team_invitation_accepted",
        "community_team_invitation_rejected",
        "community_team_member_added",
        "community_team_member_removed",
        "community_team_member_role_updated",
        "community_updated",
        "event_category_added",
        "event_category_deleted",
        "event_category_updated",
        "group_activated",
        "group_added",
        "group_category_added",
        "group_category_deleted",
        "group_category_updated",
        "group_deactivated",
        "group_deleted",
        "group_external_payments_updated",
        "group_payment_recipient_updated",
        "group_updated",
        "region_added",
        "region_deleted",
        "region_updated"
    ]'::jsonb,
    'Should list every community dashboard action and skip hidden actions'
);

-- Should list only audit rows of the selected community
select is(
    jsonb_path_query_array(
        list_community_audit_logs(:'community2ID'::uuid, '{}'::jsonb)::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'otherCommunityAuditID'),
    'Should list only audit rows of the selected community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
