-- Tests adding session proposals to an event call for sessions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

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

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_community(:'community2ID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

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
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'cfs_description', 'CFS open',
    'cfs_enabled', true,
    'cfs_ends_at', current_timestamp + interval '1 day',
    'cfs_starts_at', current_timestamp - interval '1 day',
    'ends_at', current_timestamp + interval '8 days',
    'published', true,
    'starts_at', current_timestamp + interval '7 days'
));

-- Event (closed)
select fx_event(:'eventClosedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'cfs_description', 'CFS closed',
    'cfs_enabled', true,
    'cfs_ends_at', current_timestamp + interval '3 days',
    'cfs_starts_at', current_timestamp + interval '2 days',
    'ends_at', current_timestamp + interval '11 days',
    'published', true,
    'starts_at', current_timestamp + interval '10 days'
));

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'label1ID', :'eventID', 'track / backend', '#DBEAFE'),
    (:'label2ID', :'eventID', 'track / frontend', '#FEE2E2'),
    (:'labelInvalidID', :'eventClosedID', 'track / closed-event', '#CCFBF1');

-- Event (CFS disabled)
select fx_event(:'eventDisabledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'cfs_enabled', false,
    'ends_at', current_timestamp + interval '8 days',
    'published', true,
    'starts_at', current_timestamp + interval '7 days'
));

-- Event (unpublished)
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'cfs_description', 'CFS open',
    'cfs_enabled', true,
    'cfs_ends_at', current_timestamp + interval '1 day',
    'cfs_starts_at', current_timestamp - interval '1 day',
    'ends_at', current_timestamp + interval '8 days',
    'starts_at', current_timestamp + interval '7 days'
));

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
    'OCG01',
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
    'OCG01',
    'cfs is not enabled for this event',
    'Should reject submissions when CFS is disabled'
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
