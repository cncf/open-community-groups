-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '5e010000-0000-0000-0000-000000000001'
\set communityID '5e010000-0000-0000-0000-000000000002'
\set eventCategoryID '5e010000-0000-0000-0000-000000000003'
\set eventClosedID '5e010000-0000-0000-0000-000000000004'
\set eventDisabledID '5e010000-0000-0000-0000-000000000005'
\set eventID '5e010000-0000-0000-0000-000000000006'
\set eventUnpublishedID '5e010000-0000-0000-0000-000000000007'
\set eventWindowNotConfiguredID '5e010000-0000-0000-0000-000000000008'
\set groupCategoryID '5e010000-0000-0000-0000-000000000009'
\set groupID '5e010000-0000-0000-0000-00000000000a'
\set label1ID '5e010000-0000-0000-0000-00000000000b'
\set label2ID '5e010000-0000-0000-0000-00000000000c'
\set labelInvalidID '5e010000-0000-0000-0000-00000000000d'
\set missingProposalID '5e010000-0000-0000-0000-00000000000e'
\set proposalID '5e010000-0000-0000-0000-00000000000f'
\set proposalPendingID '5e010000-0000-0000-0000-000000000010'
\set proposalWithLabelsID '5e010000-0000-0000-0000-000000000011'
\set userID '5e010000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Allow malformed legacy CFS rows for window guard coverage
alter table event drop constraint event_cfs_fields_chk;

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'cfs-community',
    'CFS Community',
    'Community for CFS submission tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'community2ID',
    'other-cfs-community',
    'Other CFS Community',
    'Other community for CFS submission tests',
    'https://example.com/other-banner-mobile.png',
    'https://example.com/other-banner.png',
    'https://example.com/other-logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'userID',
    gen_random_bytes(32),
    'alice@example.com',
    true,
    'alice',
    'Alice'
);

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'CFS Group', 'cfs-group');

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

-- Event (CFS window not configured)
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
    :'eventWindowNotConfiguredID',
    :'groupID',
    'Event Window Not Configured',
    'event-window-not-configured',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    'CFS missing window',
    true,
    null,
    null,
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

-- Should reject submissions when the CFS window is not configured
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'eventWindowNotConfiguredID',
        :'userID',
        :'proposalID'
    ),
    'cfs window not configured',
    'Should reject submissions when the CFS window is not configured'
);

-- Visibility filtering masks unpublished events, so the generic message is intentional.
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

-- Visibility filtering masks other-community events, so the generic message is intentional.
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

-- Should reject submissions for missing proposals
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'eventID',
        :'userID',
        :'missingProposalID'
    ),
    'session proposal not found',
    'Should reject submissions for missing proposals'
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
