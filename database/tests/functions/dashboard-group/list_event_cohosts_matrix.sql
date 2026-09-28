-- Tests list_event_cohosts current statuses, inactive groups, ordering, and missing events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedGroupID 'e5180000-0000-0000-0000-000000000001'
\set communityID 'e5180000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5180000-0000-0000-0000-000000000003'
\set eventID 'e5180000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5180000-0000-0000-0000-000000000005'
\set groupID 'e5180000-0000-0000-0000-000000000006'
\set inactivePendingGroupID 'e5180000-0000-0000-0000-000000000007'
\set missingEventID 'e5180000-0000-0000-0000-000000000008'
\set removedGroupID 'e5180000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, category, owner, event and co-host groups
select fx_community(:'communityID', jsonb_build_object('display_name', 'Editor Matrix', 'name', 'editor-matrix'));
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'approvedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Alpha Approved'));
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'inactivePendingGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false, 'name', 'Beta Pending'));
select fx_group(:'removedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Removed Hidden'));
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('cohosts_revision', 6));

-- Editor co-host rows
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'approvedGroupID'),
    (null, 'pending', :'eventID', :'inactivePendingGroupID'),
    ('2025-01-01 00:00:00+00', 'removed', :'eventID', :'removedGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only pending and approved current rows
select is(
    jsonb_array_length(list_event_cohosts(:'groupID'::uuid, :'eventID'::uuid)::jsonb->'cohosts'),
    2,
    'Should return only pending and approved current rows'
);

-- Should include inactive current groups with group_active false
select is(
    (
        select (item->>'group_active')::boolean
        from jsonb_array_elements(list_event_cohosts(:'groupID'::uuid, :'eventID'::uuid)::jsonb->'cohosts') item
        where item->>'group_id' = :'inactivePendingGroupID'
    ),
    false,
    'Should include inactive current groups with group_active false'
);

-- Should return rows ordered by name and include revision
select is(
    (
        select jsonb_build_object(
            'names', jsonb_agg(item->>'name'),
            'revision', list_event_cohosts(:'groupID'::uuid, :'eventID'::uuid)::jsonb->'revision'
        )
        from jsonb_array_elements(list_event_cohosts(:'groupID'::uuid, :'eventID'::uuid)::jsonb->'cohosts') item
    ),
    '{"names":["Alpha Approved","Beta Pending"],"revision":6}'::jsonb,
    'Should return rows ordered by name and include revision'
);

-- Should return an empty result for missing events
select is(
    list_event_cohosts(:'groupID'::uuid, :'missingEventID'::uuid)::jsonb,
    '{"cohosts":[],"revision":0}'::jsonb,
    'Should return an empty result for missing events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
