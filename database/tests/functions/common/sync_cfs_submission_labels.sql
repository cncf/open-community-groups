-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000021'
\set eventOtherID '00000000-0000-0000-0000-000000000022'
\set groupCategoryID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000041'
\set label1ID '00000000-0000-0000-0000-000000000051'
\set label2ID '00000000-0000-0000-0000-000000000052'
\set labelOtherID '00000000-0000-0000-0000-000000000053'
\set proposalOtherID '00000000-0000-0000-0000-000000000062'
\set proposalID '00000000-0000-0000-0000-000000000061'
\set submissionOtherID '00000000-0000-0000-0000-000000000072'
\set submissionID '00000000-0000-0000-0000-000000000071'
\set userID '00000000-0000-0000-0000-000000000081'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, email, username, auth_hash)
values (:'userID', 'speaker@example.com', 'speaker', 'hash');

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'community-1', 'Community 1', 'Test community', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Group 1', 'group-1');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

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

-- Session proposal
insert into session_proposal (
    session_proposal_id,
    user_id,
    title,
    description,
    duration,
    session_proposal_level_id
) values
    (
        :'proposalID',
        :'userID',
        'Proposal',
        'Proposal description',
        interval '45 minutes',
        'intermediate'
    ),
    (
        :'proposalOtherID',
        :'userID',
        'Other Proposal',
        'Other proposal description',
        interval '45 minutes',
        'intermediate'
    );

-- CFS submission
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values
    (:'submissionID', :'eventID', :'proposalID', 'not-reviewed'),
    (:'submissionOtherID', :'eventOtherID', :'proposalOtherID', 'not-reviewed');

-- Existing submission label
insert into cfs_submission_label (cfs_submission_id, event_cfs_label_id)
values
    (:'submissionID', :'label1ID'),
    (:'submissionOtherID', :'labelOtherID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should replace labels and remove duplicates
select lives_ok(
    format(
        $$select sync_cfs_submission_labels('%s'::uuid, '%s'::uuid, array['%s'::uuid, '%s'::uuid, '%s'::uuid])$$,
        :'submissionID',
        :'eventID',
        :'label2ID',
        :'label2ID',
        :'label1ID'
    ),
    'Should replace labels and remove duplicates'
);

select is(
    (
        select jsonb_agg(event_cfs_label_id order by event_cfs_label_id)
        from cfs_submission_label
        where cfs_submission_id = :'submissionID'::uuid
    ),
    jsonb_build_array(:'label1ID'::uuid, :'label2ID'::uuid),
    'Should store unique labels'
);

-- Should clear labels when payload is null
select lives_ok(
    format($$select sync_cfs_submission_labels('%s'::uuid, '%s'::uuid, null)$$, :'submissionID', :'eventID'),
    'Should clear labels when payload is null'
);

select is(
    (select count(*) from cfs_submission_label where cfs_submission_id = :'submissionID'::uuid),
    0::bigint,
    'Should remove existing labels'
);

-- Should reject mismatched submission and event IDs
select throws_ok(
    format(
        $$select sync_cfs_submission_labels('%s'::uuid, '%s'::uuid, array['%s'::uuid])$$,
        :'submissionOtherID',
        :'eventID',
        :'label1ID'
    ),
    'submission not found',
    'Should reject mismatched submission and event IDs'
);

select is(
    (
        select jsonb_agg(event_cfs_label_id order by event_cfs_label_id)
        from cfs_submission_label
        where cfs_submission_id = :'submissionOtherID'::uuid
    ),
    jsonb_build_array(:'labelOtherID'::uuid),
    'Should leave mismatched submission labels unchanged'
);

-- Should reject labels from another event
select throws_ok(
    format(
        $$select sync_cfs_submission_labels('%s'::uuid, '%s'::uuid, array['%s'::uuid])$$,
        :'submissionID',
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
