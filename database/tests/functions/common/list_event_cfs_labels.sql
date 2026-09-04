-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c100000-0000-0000-0000-000000000001'
\set eventCategoryID '0c100000-0000-0000-0000-000000000002'
\set eventID '0c100000-0000-0000-0000-000000000003'
\set eventNoLabelsID '0c100000-0000-0000-0000-000000000004'
\set groupCategoryID '0c100000-0000-0000-0000-000000000005'
\set groupID '0c100000-0000-0000-0000-000000000006'
\set labelAID '0c100000-0000-0000-0000-000000000007'
\set labelZID '0c100000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'eventNoLabelsID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'labelZID', :'eventID', 'track / z', '#FEE2E2'),
    (:'labelAID', :'eventID', 'track / a', '#DBEAFE');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list labels sorted by name
select is(
    list_event_cfs_labels(:'eventID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'color', '#DBEAFE',
            'event_cfs_label_id', :'labelAID'::uuid,
            'name', 'track / a'
        ),
        jsonb_build_object(
            'color', '#FEE2E2',
            'event_cfs_label_id', :'labelZID'::uuid,
            'name', 'track / z'
        )
    ),
    'Should list labels sorted by name'
);

-- Should return empty list for events without labels
select is(
    list_event_cfs_labels(:'eventNoLabelsID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty list for events without labels'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
