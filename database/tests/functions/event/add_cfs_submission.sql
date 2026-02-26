-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000041'
\set eventClosedID '00000000-0000-0000-0000-000000000052'
\set eventDisabledID '00000000-0000-0000-0000-000000000053'
\set eventID '00000000-0000-0000-0000-000000000051'
\set eventUnpublishedID '00000000-0000-0000-0000-000000000054'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set label1ID '00000000-0000-0000-0000-000000000101'
\set label2ID '00000000-0000-0000-0000-000000000102'
\set labelInvalidID '00000000-0000-0000-0000-000000000103'
\set proposalID '00000000-0000-0000-0000-000000000061'
\set proposalWithLabelsID '00000000-0000-0000-0000-000000000063'
\set proposalPendingID '00000000-0000-0000-0000-000000000062'
\set userID '00000000-0000-0000-0000-000000000071'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'community2ID', 'c2', 'C2', 'd', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'groupCategoryID', 'G1', 'g1');

-- Event category
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Meetup');

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice');

-- Session proposal
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'proposalID',
    '2024-01-02 00:00:00+00',
    'Talk about Rust',
    make_interval(mins => 45),
    'beginner',
    'Rust Intro',
    :'userID'
);

-- Session proposal
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'proposalWithLabelsID',
    '2024-01-03 00:00:00+00',
    'Talk about labels',
    make_interval(mins => 30),
    'beginner',
    'Labels Intro',
    :'userID'
);

-- Session proposal
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    session_proposal_status_id,
    title,
    user_id
) values (
    :'proposalPendingID',
    '2024-01-03 00:00:00+00',
    'Talk about Zig',
    make_interval(mins => 60),
    'intermediate',
    'pending-co-speaker-response',
    'Zig Intro',
    :'userID'
);

-- Event (open)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    cfs_description,
    cfs_enabled,
    cfs_starts_at,
    cfs_ends_at,
    starts_at,
    ends_at
) values (
    :'eventID',
    :'groupID',
    'Event 1',
    'event-1',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    'CFS open',
    true,
    current_timestamp - interval '1 day',
    current_timestamp + interval '1 day',
    current_timestamp + interval '7 days',
    current_timestamp + interval '8 days'
);

-- Event (closed)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    cfs_description,
    cfs_enabled,
    cfs_starts_at,
    cfs_ends_at,
    starts_at,
    ends_at
) values (
    :'eventClosedID',
    :'groupID',
    'Event Closed',
    'event-closed',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    'CFS closed',
    true,
    current_timestamp + interval '2 days',
    current_timestamp + interval '3 days',
    current_timestamp + interval '10 days',
    current_timestamp + interval '11 days'
);

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'label1ID', :'eventID', 'track / backend', '#DBEAFE'),
    (:'label2ID', :'eventID', 'track / frontend', '#FEE2E2'),
    (:'labelInvalidID', :'eventClosedID', 'track / closed-event', '#CCFBF1');

-- Event (CFS disabled)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    cfs_description,
    cfs_enabled,
    cfs_starts_at,
    cfs_ends_at,
    starts_at,
    ends_at
) values (
    :'eventDisabledID',
    :'groupID',
    'Event Disabled',
    'event-disabled',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    null,
    false,
    null,
    null,
    current_timestamp + interval '7 days',
    current_timestamp + interval '8 days'
);

-- Event (unpublished)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    cfs_description,
    cfs_enabled,
    cfs_starts_at,
    cfs_ends_at,
    starts_at,
    ends_at
) values (
    :'eventUnpublishedID',
    :'groupID',
    'Event Unpublished',
    'event-unpublished',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    false,
    'CFS open',
    true,
    current_timestamp - interval '1 day',
    current_timestamp + interval '1 day',
    current_timestamp + interval '7 days',
    current_timestamp + interval '8 days'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject submissions when CFS is closed
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'eventClosedID',
        :'userID',
        :'proposalID'
    ),
    'cfs is not open',
    'Should reject submissions when CFS is closed'
);

-- Should reject submissions when CFS is disabled
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'eventDisabledID',
        :'userID',
        :'proposalID'
    ),
    'cfs is not enabled for this event',
    'Should reject submissions when CFS is disabled'
);

-- Should reject submissions when event is unpublished
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'eventUnpublishedID',
        :'userID',
        :'proposalID'
    ),
    'cfs is not enabled for this event',
    'Should reject submissions when event is unpublished'
);

-- Should reject submissions when event belongs to another community
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'community2ID',
        :'eventID',
        :'userID',
        :'proposalID'
    ),
    'cfs is not enabled for this event',
    'Should reject submissions when event belongs to another community'
);

-- Add CFS submission
select lives_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'eventID',
        :'userID',
        :'proposalID'
    ),
    'Should execute add_cfs_submission successfully'
);

-- Should add CFS submission
select is(
    (
        select count(*)
        from cfs_submission
        where event_id = :'eventID'::uuid and session_proposal_id = :'proposalID'::uuid
    ),
    1::bigint,
    'Should create a CFS submission record'
);

-- Should reject duplicate CFS submissions
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'eventID',
        :'userID',
        :'proposalID'
    ),
    '23505',
    null,
    'Should reject duplicate CFS submissions'
);

-- Should reject submissions for proposals not ready for submission
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'eventID',
        :'userID',
        :'proposalPendingID'
    ),
    'session proposal not ready for submission',
    'Should reject submissions for proposals not ready for submission'
);

-- Should reject labels that do not belong to the event
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid])',
        :'communityID',
        :'eventID',
        :'userID',
        :'proposalWithLabelsID',
        :'labelInvalidID'
    ),
    'invalid event CFS labels',
    'Should reject labels that do not belong to the event'
);

-- Should execute add_cfs_submission with labels successfully
select lives_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid, %L::uuid])',
        :'communityID',
        :'eventID',
        :'userID',
        :'proposalWithLabelsID',
        :'label1ID',
        :'label2ID'
    ),
    'Should execute add_cfs_submission with labels successfully'
);

-- Should add labels to the CFS submission
select is(
    (
        select count(*)
        from cfs_submission_label csl
        join cfs_submission cs on cs.cfs_submission_id = csl.cfs_submission_id
        where cs.event_id = :'eventID'::uuid
        and cs.session_proposal_id = :'proposalWithLabelsID'::uuid
    ),
    2::bigint,
    'Should add labels to the CFS submission'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
