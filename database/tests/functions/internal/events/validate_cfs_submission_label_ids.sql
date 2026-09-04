-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

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

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, groups and events
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_event(:'eventOtherID', :'groupID', :'eventCategoryID');

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'label1ID', :'eventID', 'Track / Backend', '#DBEAFE'),
    (:'label2ID', :'eventID', 'Track / Frontend', '#FEE2E2'),
    (:'labelOtherID', :'eventOtherID', 'Track / Other', '#CCFBF1');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept null labels
select lives_ok(
    format($$select validate_cfs_submission_label_ids(%L::uuid, null)$$, :'eventID'),
    'Should accept null labels'
);

-- Should accept empty labels
select lives_ok(
    format($$select validate_cfs_submission_label_ids(%L::uuid, array[]::uuid[])$$, :'eventID'),
    'Should accept empty labels'
);

-- Should accept valid labels with duplicates
select lives_ok(
    format(
        $$select validate_cfs_submission_label_ids(%L::uuid, array[%L::uuid, %L::uuid, %L::uuid])$$,
        :'eventID',
        :'label1ID',
        :'label1ID',
        :'label2ID'
    ),
    'Should accept valid labels with duplicates'
);

-- Should reject more than ten labels
select throws_ok(
    format(
        $$select validate_cfs_submission_label_ids(
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
    'too many submission labels',
    'Should reject more than ten labels'
);

-- Should reject labels from another event
select throws_ok(
    format(
        $$select validate_cfs_submission_label_ids(%L::uuid, array[%L::uuid])$$,
        :'eventID',
        :'labelOtherID'
    ),
    'OCG01',
    'invalid event CFS labels',
    'Should reject labels from another event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
