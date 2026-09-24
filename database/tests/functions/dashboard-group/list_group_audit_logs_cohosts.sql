-- Tests list_group_audit_logs includes event co-host audit actions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e52a0000-0000-0000-0000-000000000001'
\set groupCategoryID 'e52a0000-0000-0000-0000-000000000002'
\set groupID 'e52a0000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Audit rows for every co-host action
insert into audit_log (action, community_id, group_id, resource_id, resource_type) values
    ('event_cohost_approved', :'communityID', :'groupID', gen_random_uuid(), 'event'),
    ('event_cohost_canceled', :'communityID', :'groupID', gen_random_uuid(), 'event'),
    ('event_cohost_closed', :'communityID', :'groupID', gen_random_uuid(), 'event'),
    ('event_cohost_invited', :'communityID', :'groupID', gen_random_uuid(), 'event'),
    ('event_cohost_rejected', :'communityID', :'groupID', gen_random_uuid(), 'event'),
    ('event_cohost_removed', :'communityID', :'groupID', gen_random_uuid(), 'event');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include every event co-host audit action
select is(
    (
        select jsonb_agg(log_item->>'action' order by log_item->>'action')
        from jsonb_array_elements(list_group_audit_logs(:'groupID'::uuid, '{}'::jsonb)::jsonb->'logs') log_item
    ),
    '["event_cohost_approved","event_cohost_canceled","event_cohost_closed","event_cohost_invited","event_cohost_rejected","event_cohost_removed"]'::jsonb,
    'Should include every event co-host audit action'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
