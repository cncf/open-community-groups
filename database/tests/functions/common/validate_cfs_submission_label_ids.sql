-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000021'
\set eventOtherID '00000000-0000-0000-0000-000000000022'
\set groupCategoryID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000041'
\set label1ID '00000000-0000-0000-0000-000000000051'
\set label2ID '00000000-0000-0000-0000-000000000052'
\set labelOtherID '00000000-0000-0000-0000-000000000053'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'alliance-1', 'Alliance 1', 'Test alliance', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Group 1', 'group-1');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Meetup');

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
) values
    (:'eventID', :'groupID', 'Labels Event', 'labels-event', 'Test event', 'UTC', :'eventCategoryID', 'in-person'),
    (:'eventOtherID', :'groupID', 'Other Labels Event', 'other-labels-event', 'Test event', 'UTC', :'eventCategoryID', 'in-person');

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
    format($$select validate_cfs_submission_label_ids('%s'::uuid, null)$$, :'eventID'),
    'Should accept null labels'
);

-- Should accept empty labels
select lives_ok(
    format($$select validate_cfs_submission_label_ids('%s'::uuid, array[]::uuid[])$$, :'eventID'),
    'Should accept empty labels'
);

-- Should accept valid labels with duplicates
select lives_ok(
    format(
        $$select validate_cfs_submission_label_ids('%s'::uuid, array['%s'::uuid, '%s'::uuid, '%s'::uuid])$$,
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
            '%s'::uuid,
            array[
                '%s'::uuid, '%s'::uuid, '%s'::uuid, '%s'::uuid,
                '%s'::uuid, '%s'::uuid, '%s'::uuid, '%s'::uuid,
                '%s'::uuid, '%s'::uuid, '%s'::uuid
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
        $$select validate_cfs_submission_label_ids('%s'::uuid, array['%s'::uuid])$$,
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
