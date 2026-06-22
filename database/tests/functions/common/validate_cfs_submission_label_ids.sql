-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '0c1d0000-0000-0000-0000-000000000001'
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

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'cfs-label-validation-alliance',
    'CFS Label Validation Alliance',
    'Alliance for CFS label validation tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Meetup');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'CFS Label Validation Group',
    'cfs-label-validation-group'
);

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'eventID',
    :'groupID',
    'Labels Event',
    'labels-event',
    'Test event',
    'UTC',
    :'eventCategoryID',
    'in-person'
), (
    :'eventOtherID',
    :'groupID',
    'Other Labels Event',
    'other-labels-event',
    'Test event',
    'UTC',
    :'eventCategoryID',
    'in-person'
);

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
    'invalid event CFS labels',
    'Should reject labels from another event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
