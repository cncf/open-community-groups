-- Tests validating the event label IDs assigned to a submission or session.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c1d0000-0000-0000-0000-000000000001'
\set eventCategoryID '0c1d0000-0000-0000-0000-000000000002'
\set eventID '0c1d0000-0000-0000-0000-000000000003'
\set eventOtherID '0c1d0000-0000-0000-0000-000000000004'
\set groupCategoryID '0c1d0000-0000-0000-0000-000000000005'
\set groupID '0c1d0000-0000-0000-0000-000000000006'
\set label1ID '0c1d0000-0000-0000-0000-000000000007'
\set label2ID '0c1d0000-0000-0000-0000-000000000008'
\set labelOtherID '0c1d0000-0000-0000-0000-000000000009'
\set missingLabelID '0c1d0000-0000-0000-0000-00000000000a'

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

-- Event whose labels are assigned
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event owning a label that cannot be assigned
select fx_event(:'eventOtherID', :'groupID', :'eventCategoryID');

-- First assignable label
insert into event_label (event_label_id, color, event_id, name)
values (:'label1ID', '#DBEAFE', :'eventID', 'Track / Backend');

-- Second assignable label
insert into event_label (event_label_id, color, event_id, name)
values (:'label2ID', '#FEE2E2', :'eventID', 'Track / Frontend');

-- Label belonging to another event
insert into event_label (event_label_id, color, event_id, name)
values (:'labelOtherID', '#CCFBF1', :'eventOtherID', 'Track / Other');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept empty labels
select lives_ok(
    format($$select validate_event_label_ids(%L::uuid, array[]::uuid[])$$, :'eventID'),
    'Should accept empty labels'
);

-- Should accept null labels
select lives_ok(
    format($$select validate_event_label_ids(%L::uuid, null)$$, :'eventID'),
    'Should accept null labels'
);

-- Should accept ten labels
select lives_ok(
    format(
        $$select validate_event_label_ids(
            %L::uuid,
            array[
                %L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid,
                %L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid
            ]
        )$$,
        :'eventID',
        :'label1ID', :'label2ID', :'label1ID', :'label2ID', :'label1ID',
        :'label2ID', :'label1ID', :'label2ID', :'label1ID', :'label2ID'
    ),
    'Should accept ten labels'
);

-- Should accept valid labels with duplicates
select lives_ok(
    format(
        $$select validate_event_label_ids(%L::uuid, array[%L::uuid, %L::uuid, %L::uuid])$$,
        :'eventID',
        :'label1ID',
        :'label1ID',
        :'label2ID'
    ),
    'Should accept valid labels with duplicates'
);

-- Should reject labels from another event
select throws_ok(
    format(
        $$select validate_event_label_ids(%L::uuid, array[%L::uuid, %L::uuid])$$,
        :'eventID',
        :'label1ID',
        :'labelOtherID'
    ),
    'OCG01',
    'invalid event labels',
    'Should reject labels from another event'
);

-- Should reject more than ten labels
select throws_ok(
    format(
        $$select validate_event_label_ids(
            %L::uuid,
            array[
                %L::uuid, %L::uuid, %L::uuid, %L::uuid,
                %L::uuid, %L::uuid, %L::uuid, %L::uuid,
                %L::uuid, %L::uuid, %L::uuid
            ]
        )$$,
        :'eventID',
        :'label1ID', :'label1ID', :'label1ID', :'label1ID',
        :'label1ID', :'label1ID', :'label1ID', :'label1ID',
        :'label1ID', :'label1ID', :'label1ID'
    ),
    'OCG01',
    'too many labels',
    'Should reject more than ten labels'
);

-- Should reject unknown labels
select throws_ok(
    format(
        $$select validate_event_label_ids(%L::uuid, array[%L::uuid])$$,
        :'eventID',
        :'missingLabelID'
    ),
    'OCG01',
    'invalid event labels',
    'Should reject unknown labels'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
