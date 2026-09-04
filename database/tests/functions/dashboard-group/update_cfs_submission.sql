-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a380000-0000-0000-0000-000000000001'
\set event2ID '3a380000-0000-0000-0000-000000000002'
\set eventCategoryID '3a380000-0000-0000-0000-000000000003'
\set eventID '3a380000-0000-0000-0000-000000000004'
\set groupCategoryID '3a380000-0000-0000-0000-000000000005'
\set groupID '3a380000-0000-0000-0000-000000000006'
\set label1ID '3a380000-0000-0000-0000-000000000007'
\set label2ID '3a380000-0000-0000-0000-000000000008'
\set labelInvalidID '3a380000-0000-0000-0000-000000000009'
\set proposal2ID '3a380000-0000-0000-0000-000000000010'
\set proposal3ID '3a380000-0000-0000-0000-000000000011'
\set proposalID '3a380000-0000-0000-0000-000000000012'
\set reviewerID '3a380000-0000-0000-0000-000000000013'
\set submission2ID '3a380000-0000-0000-0000-000000000014'
\set submission3ID '3a380000-0000-0000-0000-000000000015'
\set submissionID '3a380000-0000-0000-0000-000000000016'
\set userID '3a380000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'reviewerID', jsonb_build_object('username', 'reviewer'));

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
), (
    :'proposal2ID',
    '2024-01-03 00:00:00+00',
    'Talk about SQL',
    make_interval(mins => 30),
    'beginner',
    'SQL Tuning',
    :'userID'
), (
    :'proposal3ID',
    '2024-01-04 00:00:00+00',
    'Talk about Postgres',
    make_interval(mins => 40),
    'beginner',
    'Postgres Basics',
    :'userID'
);

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event used for invalid label checks
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'label1ID', :'eventID', 'track / backend', '#DBEAFE'),
    (:'label2ID', :'eventID', 'track / frontend', '#FEE2E2'),
    (:'labelInvalidID', :'event2ID', 'track / invalid', '#CCFBF1');

-- CFS submission
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values
    (:'submissionID', :'eventID', :'proposalID', 'not-reviewed'),
    (:'submission2ID', :'eventID', :'proposal2ID', 'withdrawn'),
    (:'submission3ID', :'eventID', :'proposal3ID', 'approved');

-- CFS submission labels
insert into cfs_submission_label (cfs_submission_id, event_cfs_label_id)
values (:'submissionID', :'label1ID');

-- Session
insert into session (
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    cfs_submission_id
) values (
    :'eventID',
    'Session 1',
    'in-person',
    '2024-01-02 10:00:00+00',
    '2024-01-02 11:00:00+00',
    :'submission3ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return true when status or message changes
select is(
    (
        select update_cfs_submission(
            :'reviewerID'::uuid,
            :'eventID'::uuid,
            :'submissionID'::uuid,
            jsonb_build_object(
                'action_required_message', 'Need more info',
                'status_id', 'information-requested'
            )
        )
    ),
    true,
    'Should return true when status or message changes'
);

-- Should update submission status
select is(
    (select status_id from cfs_submission where cfs_submission_id = :'submissionID'::uuid),
    'information-requested',
    'Should update submission status'
);

-- Should store action required message
select is(
    (select action_required_message from cfs_submission where cfs_submission_id = :'submissionID'::uuid),
    'Need more info',
    'Should store action required message'
);

-- Should store reviewer
select is(
    (select reviewed_by from cfs_submission where cfs_submission_id = :'submissionID'::uuid),
    :'reviewerID'::uuid,
    'Should store reviewer'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            event_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'cfs_submission_updated',
            %L::uuid,
            'reviewer',
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'cfs_submission',
            %L::uuid
        )
        $$,
        :'reviewerID',
        :'communityID',
        :'groupID',
        :'eventID',
        :'submissionID'
    ),
    'Should create the expected audit row'
);

-- Should return false when only labels change
select is(
    (
        select update_cfs_submission(
            :'reviewerID'::uuid,
            :'eventID'::uuid,
            :'submissionID'::uuid,
            format(
                '{"action_required_message":"Need more info","status_id":"information-requested","label_ids":["%s"]}',
                :'label2ID'
            )::jsonb
        )
    ),
    false,
    'Should return false when only labels change'
);

-- Should replace submission labels
select is(
    (
        select jsonb_agg(event_cfs_label_id order by event_cfs_label_id)
        from cfs_submission_label
        where cfs_submission_id = :'submissionID'::uuid
    ),
    jsonb_build_array(:'label2ID'::uuid),
    'Should replace submission labels'
);

-- Should return false when only rating changes
select is(
    (
        select update_cfs_submission(
            :'reviewerID'::uuid,
            :'eventID'::uuid,
            :'submissionID'::uuid,
            jsonb_build_object(
                'action_required_message', 'Need more info',
                'status_id', 'information-requested',
                'rating_comment', 'Needs a stronger conclusion',
                'rating_stars', 4
            )
        )
    ),
    false,
    'Should return false when only rating changes'
);

-- Should upsert reviewer rating
select is(
    (
        select row_to_json(r)::jsonb
        from (
            select comments, stars
            from cfs_submission_rating
            where cfs_submission_id = :'submissionID'::uuid
            and reviewer_id = :'reviewerID'::uuid
        ) r
    ),
    jsonb_build_object(
        'comments', 'Needs a stronger conclusion',
        'stars', 4
    ),
    'Should upsert reviewer rating'
);

-- Should update reviewer rating without duplicating rows
select lives_ok(
    format(
        $$
        select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            jsonb_build_object(
                'action_required_message', 'Need more info',
                'status_id', 'information-requested',
                'rating_comment', 'Great improvements',
                'rating_stars', 5
            )
        )
        $$,
        :'reviewerID', :'eventID', :'submissionID'
    ),
    'Should update an existing reviewer rating without error'
);

select is(
    (
        select count(*)::int
        from cfs_submission_rating
        where cfs_submission_id = :'submissionID'::uuid
        and reviewer_id = :'reviewerID'::uuid
    ),
    1,
    'Should update reviewer rating without duplicating rows'
);

-- Should clear reviewer rating when stars are zero
select lives_ok(
    format(
        $$
        select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            jsonb_build_object(
                'action_required_message', 'Need more info',
                'status_id', 'information-requested',
                'rating_stars', 0
            )
        )
        $$,
        :'reviewerID', :'eventID', :'submissionID'
    ),
    'Should accept a zero stars rating without error'
);

select is(
    (
        select count(*)::int
        from cfs_submission_rating
        where cfs_submission_id = :'submissionID'::uuid
        and reviewer_id = :'reviewerID'::uuid
    ),
    0,
    'Should clear reviewer rating when stars are zero'
);

-- Should reject invalid rating stars
select throws_ok(
    format(
        $$select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::jsonb
        )$$,
        :'reviewerID',
        :'eventID',
        :'submissionID',
        '{"action_required_message":"Need more info","status_id":"information-requested","rating_stars":6}'
    ),
    'OCG01',
    'invalid rating stars',
    'Should reject invalid rating stars'
);

-- Should reject status changes for linked submissions
select throws_ok(
    format(
        $$select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::jsonb
        )$$,
        :'reviewerID',
        :'eventID',
        :'submission3ID',
        '{"status_id":"rejected"}'
    ),
    'OCG01',
    'linked submissions must remain approved',
    'Should reject status changes for linked submissions'
);

-- Should reject withdrawn status updates
select throws_ok(
    format(
        $$select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::jsonb
        )$$,
        :'reviewerID',
        :'eventID',
        :'submissionID',
        '{"status_id":"withdrawn"}'
    ),
    'OCG01',
    'invalid submission status',
    'Should reject withdrawn status updates'
);

-- Should reject updating withdrawn submissions
select throws_ok(
    format(
        $$select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::jsonb
        )$$,
        :'reviewerID',
        :'eventID',
        :'submission2ID',
        '{"status_id":"approved"}'
    ),
    'OCG01',
    'submission not found',
    'Should reject updating withdrawn submissions'
);

-- Should reject labels that do not belong to the event
select throws_ok(
    format(
        $$select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::jsonb
        )$$,
        :'reviewerID',
        :'eventID',
        :'submissionID',
        format(
            '{"status_id":"information-requested","label_ids":["%s"]}',
            :'labelInvalidID'
        )
    ),
    'OCG01',
    'invalid event CFS labels',
    'Should reject labels that do not belong to the event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
