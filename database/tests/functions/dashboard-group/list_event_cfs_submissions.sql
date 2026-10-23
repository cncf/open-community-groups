-- Tests listing CFS submissions for an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a1a0000-0000-0000-0000-000000000001'
\set deletedEventID '3a1a0000-0000-0000-0000-000000000028'
\set deletedEventSubmissionID '3a1a0000-0000-0000-0000-000000000029'
\set eventCategoryID '3a1a0000-0000-0000-0000-000000000002'
\set eventEmptyID '3a1a0000-0000-0000-0000-000000000003'
\set eventID '3a1a0000-0000-0000-0000-000000000004'
\set eventSortID '3a1a0000-0000-0000-0000-000000000005'
\set groupCategoryID '3a1a0000-0000-0000-0000-000000000006'
\set groupID '3a1a0000-0000-0000-0000-000000000007'
\set label1ID '3a1a0000-0000-0000-0000-000000000008'
\set label2ID '3a1a0000-0000-0000-0000-000000000009'
\set otherGroupID '3a1a0000-0000-0000-0000-000000000027'
\set proposal1ID '3a1a0000-0000-0000-0000-000000000010'
\set proposal2ID '3a1a0000-0000-0000-0000-000000000011'
\set proposal3ID '3a1a0000-0000-0000-0000-000000000012'
\set proposal4ID '3a1a0000-0000-0000-0000-000000000013'
\set reviewer1ID '3a1a0000-0000-0000-0000-000000000014'
\set reviewer2ID '3a1a0000-0000-0000-0000-000000000015'
\set reviewer3ID '3a1a0000-0000-0000-0000-000000000016'
\set sessionID '3a1a0000-0000-0000-0000-000000000017'
\set sortSubmission1ID '3a1a0000-0000-0000-0000-000000000018'
\set sortSubmission2ID '3a1a0000-0000-0000-0000-000000000019'
\set sortSubmission3ID '3a1a0000-0000-0000-0000-000000000020'
\set sortSubmission4ID '3a1a0000-0000-0000-0000-000000000021'
\set submission1ID '3a1a0000-0000-0000-0000-000000000022'
\set submission2ID '3a1a0000-0000-0000-0000-000000000023'
\set submission3ID '3a1a0000-0000-0000-0000-000000000024'
\set user1ID '3a1a0000-0000-0000-0000-000000000025'
\set user2ID '3a1a0000-0000-0000-0000-000000000026'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- First reviewer
select fx_user(:'reviewer1ID', jsonb_build_object('username', 'reviewer-1'));

-- Second reviewer
select fx_user(:'reviewer2ID', jsonb_build_object('username', 'reviewer-2'));

-- Third reviewer, used only by the sort event
select fx_user(:'reviewer3ID', jsonb_build_object('username', 'reviewer-3-list-event-cfs-submissions'));

-- Speaker of the Rust and SQL proposals
select fx_user(:'user1ID', jsonb_build_object('username', 'alice-list-event-cfs-submissions'));

-- Speaker of the Go and Postgres proposals
select fx_user(:'user2ID', jsonb_build_object('username', 'bob-list-event-cfs-submissions'));

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Session proposals
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values
    (
        :'proposal1ID',
        '2024-01-02 00:00:00+00',
        'Talk about Rust',
        make_interval(mins => 45),
        'beginner',
        'Rust Intro',
        :'user1ID'
    ),
    (
        :'proposal2ID',
        '2024-01-03 00:00:00+00',
        'Talk about Go',
        make_interval(mins => 60),
        'intermediate',
        'Go Intro',
        :'user2ID'
    ),
    (
        :'proposal3ID',
        '2024-01-04 00:00:00+00',
        'Talk about SQL',
        make_interval(mins => 30),
        'beginner',
        'SQL Tuning',
        :'user1ID'
    ),
    (
        :'proposal4ID',
        '2024-01-05 00:00:00+00',
        'Talk about Postgres',
        make_interval(mins => 30),
        'intermediate',
        'Postgres Internals',
        :'user2ID'
    );

-- Group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group that owns none of the events
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Event description',
    'published', true
));

-- Empty event
select fx_event(:'eventEmptyID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Event description',
    'published', true
));

-- Sort event, whose submissions give a distinct order per sort key
select fx_event(:'eventSortID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Event description',
    'published', true
));

-- Deleted event of the owning group
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));

-- CFS submissions
insert into cfs_submission (
    cfs_submission_id,
    created_at,
    event_id,
    session_proposal_id,
    status_id,
    action_required_message,
    reviewed_by,
    updated_at
) values
    (
        :'submission1ID',
        '2024-01-04 00:00:00+00',
        :'eventID',
        :'proposal1ID',
        'not-reviewed',
        null,
        null,
        '2024-02-01 00:00:00+00'
    ),
    (
        :'submission2ID',
        '2024-01-05 00:00:00+00',
        :'eventID',
        :'proposal2ID',
        'approved',
        'Looks good',
        :'reviewer1ID',
        '2024-01-06 00:00:00+00'
    ),
    (
        :'submission3ID',
        '2024-01-06 00:00:00+00',
        :'eventID',
        :'proposal3ID',
        'withdrawn',
        null,
        null,
        '2024-01-07 00:00:00+00'
    );

-- Sort event submissions created in id order (the fourth one stays unrated)
insert into cfs_submission (
    cfs_submission_id,
    created_at,
    event_id,
    session_proposal_id,
    status_id
) values
    (:'sortSubmission1ID', '2024-01-01 00:00:00+00', :'eventSortID', :'proposal1ID', 'not-reviewed'),
    (:'sortSubmission2ID', '2024-01-02 00:00:00+00', :'eventSortID', :'proposal2ID', 'not-reviewed'),
    (:'sortSubmission3ID', '2024-01-03 00:00:00+00', :'eventSortID', :'proposal3ID', 'not-reviewed'),
    (:'sortSubmission4ID', '2024-01-04 00:00:00+00', :'eventSortID', :'proposal4ID', 'not-reviewed');

-- Deleted event submission
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id
) values (:'deletedEventSubmissionID', :'deletedEventID', :'proposal1ID', 'not-reviewed');

-- Event labels
insert into event_label (event_label_id, event_id, name, color) values
    (:'label1ID', :'eventID', 'track / backend', '#DBEAFE'),
    (:'label2ID', :'eventID', 'track / frontend', '#FEE2E2');

-- CFS submission labels
insert into cfs_submission_label (cfs_submission_id, event_label_id) values
    (:'submission1ID', :'label1ID'),
    (:'submission2ID', :'label1ID'),
    (:'submission2ID', :'label2ID');

-- Submission ratings
insert into cfs_submission_rating (
    cfs_submission_id,
    reviewer_id,
    stars,
    comments,
    created_at
) values
    (
        :'submission1ID',
        :'reviewer1ID',
        2,
        'Needs more detail',
        '2024-02-03 00:00:00+00'
    ),
    (
        :'submission2ID',
        :'reviewer1ID',
        4,
        'Promising topic',
        '2024-02-01 00:00:00+00'
    ),
    (
        :'submission2ID',
        :'reviewer2ID',
        5,
        'Excellent fit',
        '2024-02-02 00:00:00+00'
    );

-- Sort event ratings: 3 ratings averaging 4.0, 1 rating of 5.0 and 2 ratings averaging 3.0
insert into cfs_submission_rating (
    cfs_submission_id,
    reviewer_id,
    stars
) values
    (:'sortSubmission1ID', :'reviewer1ID', 3),
    (:'sortSubmission1ID', :'reviewer2ID', 4),
    (:'sortSubmission1ID', :'reviewer3ID', 5),
    (:'sortSubmission2ID', :'reviewer1ID', 5),
    (:'sortSubmission3ID', :'reviewer1ID', 2),
    (:'sortSubmission3ID', :'reviewer2ID', 4);

-- Session
insert into session (
    session_id,
    cfs_submission_id,
    event_id,
    name,
    session_kind_id,
    starts_at
) values (
    :'sessionID',
    :'submission2ID',
    :'eventID',
    'Session 1',
    'in-person',
    '2024-02-01 10:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list event submissions
select is(
    list_event_cfs_submissions(:'groupID'::uuid, :'eventID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions', jsonb_build_array(
            jsonb_build_object(
                'action_required_message', 'Looks good',
                'average_rating', 4.5,
                'cfs_submission_id', :'submission2ID'::uuid,
                'created_at', (select epoch_seconds(created_at) from cfs_submission
                    where cfs_submission_id = :'submission2ID'::uuid),
                'labels', jsonb_build_array(
                    jsonb_build_object(
                        'color', '#DBEAFE',
                        'event_label_id', :'label1ID'::uuid,
                        'name', 'track / backend'
                    ),
                    jsonb_build_object(
                        'color', '#FEE2E2',
                        'event_label_id', :'label2ID'::uuid,
                        'name', 'track / frontend'
                    )
                ),
                'linked_session_id', :'sessionID'::uuid,
                'ratings', jsonb_build_array(
                    jsonb_build_object(
                        'comments', 'Excellent fit',
                        'reviewer', jsonb_build_object(
                            'user_id', :'reviewer2ID'::uuid,
                            'username', 'reviewer-2'
                        ),
                        'stars', 5
                    ),
                    jsonb_build_object(
                        'comments', 'Promising topic',
                        'reviewer', jsonb_build_object(
                            'user_id', :'reviewer1ID'::uuid,
                            'username', 'reviewer-1'
                        ),
                        'stars', 4
                    )
                ),
                'ratings_count', 2,
                'session_proposal', jsonb_build_object(
                    'description', 'Talk about Go',
                    'duration_minutes', 60,
                    'session_proposal_id', :'proposal2ID'::uuid,
                    'session_proposal_level_id', 'intermediate',
                    'session_proposal_level_name', 'Intermediate',
                    'title', 'Go Intro'
                ),
                'reviewed_by', jsonb_build_object(
                    'user_id', :'reviewer1ID'::uuid,
                    'username', 'reviewer-1'
                ),
                'speaker', jsonb_build_object(
                    'user_id', :'user2ID'::uuid,
                    'username', 'bob-list-event-cfs-submissions'
                ),
                'status_id', 'approved',
                'status_name', 'Approved',
                'updated_at', (select epoch_seconds(updated_at) from cfs_submission
                    where cfs_submission_id = :'submission2ID'::uuid)
            ),
            jsonb_build_object(
                'action_required_message', null,
                'average_rating', 2.0,
                'cfs_submission_id', :'submission1ID'::uuid,
                'created_at', (select epoch_seconds(created_at) from cfs_submission
                    where cfs_submission_id = :'submission1ID'::uuid),
                'labels', jsonb_build_array(
                    jsonb_build_object(
                        'color', '#DBEAFE',
                        'event_label_id', :'label1ID'::uuid,
                        'name', 'track / backend'
                    )
                ),
                'linked_session_id', null,
                'ratings', jsonb_build_array(
                    jsonb_build_object(
                        'comments', 'Needs more detail',
                        'reviewer', jsonb_build_object(
                            'user_id', :'reviewer1ID'::uuid,
                            'username', 'reviewer-1'
                        ),
                        'stars', 2
                    )
                ),
                'ratings_count', 1,
                'session_proposal', jsonb_build_object(
                    'description', 'Talk about Rust',
                    'duration_minutes', 45,
                    'session_proposal_id', :'proposal1ID'::uuid,
                    'session_proposal_level_id', 'beginner',
                    'session_proposal_level_name', 'Beginner',
                    'title', 'Rust Intro'
                ),
                'reviewed_by', null,
                'speaker', jsonb_build_object(
                    'user_id', :'user1ID'::uuid,
                    'username', 'alice-list-event-cfs-submissions'
                ),
                'status_id', 'not-reviewed',
                'status_name', 'Not reviewed',
                'updated_at', (select epoch_seconds(updated_at) from cfs_submission
                    where cfs_submission_id = :'submission1ID'::uuid)
            )
        ),
        'total', 2
    ),
    'Should list event submissions excluding withdrawn'
);

-- Should paginate submissions
select is(
    (
        list_event_cfs_submissions(:'groupID'::uuid, :'eventID'::uuid, '{"limit": 1, "offset": 1}'::jsonb)::jsonb
        -> 'submissions' -> 0 ->> 'cfs_submission_id'
    )::uuid,
    :'submission1ID'::uuid,
    'Should paginate submissions'
);

-- Should return empty submissions for deleted events
select is(
    list_event_cfs_submissions(:'groupID'::uuid, :'deletedEventID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty submissions for deleted events'
);

-- Should return empty submissions for events outside the group
select is(
    list_event_cfs_submissions(:'otherGroupID'::uuid, :'eventID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty submissions for events outside the group'
);

-- Should return empty submissions for events without submissions
select is(
    list_event_cfs_submissions(:'groupID'::uuid, :'eventEmptyID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty submissions for events without submissions'
);

-- Should filter submissions requiring all selected labels
select is(
    list_event_cfs_submissions(
        :'groupID'::uuid,
        :'eventID'::uuid,
        format(
            '{"limit": 10, "offset": 0, "label_ids": ["%s", "%s"]}',
            :'label1ID',
            :'label2ID'
        )::jsonb
    )::jsonb -> 'submissions',
    jsonb_build_array(
        jsonb_build_object(
            'action_required_message', 'Looks good',
            'average_rating', 4.5,
            'cfs_submission_id', :'submission2ID'::uuid,
            'created_at', (select epoch_seconds(created_at) from cfs_submission
                where cfs_submission_id = :'submission2ID'::uuid),
            'labels', jsonb_build_array(
                jsonb_build_object(
                    'color', '#DBEAFE',
                    'event_label_id', :'label1ID'::uuid,
                    'name', 'track / backend'
                ),
                jsonb_build_object(
                    'color', '#FEE2E2',
                    'event_label_id', :'label2ID'::uuid,
                    'name', 'track / frontend'
                )
            ),
            'linked_session_id', :'sessionID'::uuid,
            'ratings', jsonb_build_array(
                jsonb_build_object(
                    'comments', 'Excellent fit',
                    'reviewer', jsonb_build_object(
                        'user_id', :'reviewer2ID'::uuid,
                        'username', 'reviewer-2'
                    ),
                    'stars', 5
                ),
                jsonb_build_object(
                    'comments', 'Promising topic',
                    'reviewer', jsonb_build_object(
                        'user_id', :'reviewer1ID'::uuid,
                        'username', 'reviewer-1'
                    ),
                    'stars', 4
                )
            ),
            'ratings_count', 2,
            'session_proposal', jsonb_build_object(
                'description', 'Talk about Go',
                'duration_minutes', 60,
                'session_proposal_id', :'proposal2ID'::uuid,
                'session_proposal_level_id', 'intermediate',
                'session_proposal_level_name', 'Intermediate',
                'title', 'Go Intro'
            ),
            'reviewed_by', jsonb_build_object(
                'user_id', :'reviewer1ID'::uuid,
                'username', 'reviewer-1'
            ),
            'speaker', jsonb_build_object(
                'user_id', :'user2ID'::uuid,
                'username', 'bob-list-event-cfs-submissions'
            ),
            'status_id', 'approved',
            'status_name', 'Approved',
            'updated_at', (select epoch_seconds(updated_at) from cfs_submission
                where cfs_submission_id = :'submission2ID'::uuid)
        )
    ),
    'Should filter submissions requiring all selected labels'
);

-- Should sort submissions by each sort key, falling back to created date descending
select results_eq(
    format(
        $$
            select
                sorts.sort_key,
                array(
                    select (listed.submission->>'cfs_submission_id')::uuid
                    from jsonb_array_elements(
                        list_event_cfs_submissions(
                            %L::uuid,
                            %L::uuid,
                            jsonb_build_object('limit', 10, 'offset', 0, 'sort', sorts.sort_key)
                        )::jsonb->'submissions'
                    ) with ordinality as listed(submission, position)
                    order by listed.position
                ) as submission_ids
            from (
                values
                    (1, 'created-asc'),
                    (2, 'created-desc'),
                    (3, 'ratings-count-asc'),
                    (4, 'ratings-count-desc'),
                    (5, 'stars-asc'),
                    (6, 'stars-desc'),
                    (7, 'unknown')
            ) as sorts(position, sort_key)
            order by sorts.position
        $$,
        :'groupID',
        :'eventSortID'
    ),
    format(
        $$
            values
                ('created-asc', array[%1$L, %2$L, %3$L, %4$L]::uuid[]),
                ('created-desc', array[%4$L, %3$L, %2$L, %1$L]::uuid[]),
                ('ratings-count-asc', array[%4$L, %2$L, %3$L, %1$L]::uuid[]),
                ('ratings-count-desc', array[%1$L, %3$L, %2$L, %4$L]::uuid[]),
                ('stars-asc', array[%3$L, %1$L, %2$L, %4$L]::uuid[]),
                ('stars-desc', array[%2$L, %1$L, %3$L, %4$L]::uuid[]),
                ('unknown', array[%4$L, %3$L, %2$L, %1$L]::uuid[])
        $$,
        :'sortSubmission1ID',
        :'sortSubmission2ID',
        :'sortSubmission3ID',
        :'sortSubmission4ID'
    ),
    'Should sort submissions by each sort key, falling back to created date descending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
