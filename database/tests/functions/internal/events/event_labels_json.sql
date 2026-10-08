-- Tests building the JSON payload for event labels.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1abe1000-0000-0000-0000-000000000001'
\set eventCategoryID '1abe1000-0000-0000-0000-000000000002'
\set eventID '1abe1000-0000-0000-0000-000000000003'
\set groupCategoryID '1abe1000-0000-0000-0000-000000000004'
\set groupID '1abe1000-0000-0000-0000-000000000005'
\set labelBackendID '1abe1000-0000-0000-0000-000000000006'
\set labelFrontendID '1abe1000-0000-0000-0000-000000000007'
\set labelFrontendOtherID '1abe1000-0000-0000-0000-000000000008'
\set missingLabelID '1abe1000-0000-0000-0000-000000000009'
\set otherEventID '1abe1000-0000-0000-0000-00000000000a'

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

-- Event owning most labels
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event owning a label that shares a name with another event label
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Label sorted first by name
insert into event_label (event_label_id, color, event_id, name)
values (:'labelBackendID', '#DBEAFE', :'eventID', 'Backend');

-- Label sorted before its namesake by identifier
insert into event_label (event_label_id, color, event_id, name)
values (:'labelFrontendID', '#FEE2E2', :'eventID', 'Frontend');

-- Label sorted after its namesake by identifier
insert into event_label (event_label_id, color, event_id, name)
values (:'labelFrontendOtherID', '#CCFBF1', :'otherEventID', 'Frontend');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should order labels by name and then by identifier
select is(
    event_labels_json(
        array[
            :'labelFrontendOtherID'::uuid,
            :'labelFrontendID'::uuid,
            :'labelBackendID'::uuid
        ]
    )::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'color', '#DBEAFE',
            'event_label_id', :'labelBackendID'::uuid,
            'name', 'Backend'
        ),
        jsonb_build_object(
            'color', '#FEE2E2',
            'event_label_id', :'labelFrontendID'::uuid,
            'name', 'Frontend'
        ),
        jsonb_build_object(
            'color', '#CCFBF1',
            'event_label_id', :'labelFrontendOtherID'::uuid,
            'name', 'Frontend'
        )
    ),
    'Should order labels by name and then by identifier'
);

-- Should return an empty array for a null input
select is(
    event_labels_json(null)::jsonb,
    '[]'::jsonb,
    'Should return an empty array for a null input'
);

-- Should return an empty array for an empty input
select is(
    event_labels_json(array[]::uuid[])::jsonb,
    '[]'::jsonb,
    'Should return an empty array for an empty input'
);

-- Should skip unknown label identifiers
select is(
    event_labels_json(array[:'missingLabelID'::uuid, :'labelBackendID'::uuid])::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'color', '#DBEAFE',
            'event_label_id', :'labelBackendID'::uuid,
            'name', 'Backend'
        )
    ),
    'Should skip unknown label identifiers'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
