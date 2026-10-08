-- Tests listing the labels available for an event.

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
\set labelOtherEventID '0c100000-0000-0000-0000-000000000008'
\set labelZID '0c100000-0000-0000-0000-000000000009'
\set otherEventID '0c100000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the labeled events
select fx_community(:'communityID');

-- Event category used by the labeled events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the labeled events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the labeled events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose labels are listed
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event without labels
select fx_event(:'eventNoLabelsID', :'groupID', :'eventCategoryID');

-- Event whose labels must not leak into other listings
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Label sorted first by name
insert into event_label (event_label_id, color, event_id, name)
values (:'labelAID', '#DBEAFE', :'eventID', 'track / a');

-- Label belonging to another event
insert into event_label (event_label_id, color, event_id, name)
values (:'labelOtherEventID', '#CCFBF1', :'otherEventID', 'track / b');

-- Label sorted last by name
insert into event_label (event_label_id, color, event_id, name)
values (:'labelZID', '#FEE2E2', :'eventID', 'track / z');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list the event labels sorted by name
select is(
    list_event_labels(:'eventID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'color', '#DBEAFE',
            'event_label_id', :'labelAID'::uuid,
            'name', 'track / a'
        ),
        jsonb_build_object(
            'color', '#FEE2E2',
            'event_label_id', :'labelZID'::uuid,
            'name', 'track / z'
        )
    ),
    'Should list the event labels sorted by name'
);

-- Should return an empty list for events without labels
select is(
    list_event_labels(:'eventNoLabelsID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return an empty list for events without labels'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
