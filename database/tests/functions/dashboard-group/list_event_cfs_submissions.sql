-- Tests listing CFS submissions for an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a1a0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a1a0000-0000-0000-0000-000000000002'
\set eventEmptyID '3a1a0000-0000-0000-0000-000000000003'
\set eventID '3a1a0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a1a0000-0000-0000-0000-000000000005'
\set groupID '3a1a0000-0000-0000-0000-000000000006'
\set label1ID '3a1a0000-0000-0000-0000-000000000007'
\set label2ID '3a1a0000-0000-0000-0000-000000000008'
\set proposal1ID '3a1a0000-0000-0000-0000-000000000009'
\set proposal2ID '3a1a0000-0000-0000-0000-000000000010'
\set proposal3ID '3a1a0000-0000-0000-0000-000000000011'
\set reviewer1ID '3a1a0000-0000-0000-0000-000000000012'
\set reviewer2ID '3a1a0000-0000-0000-0000-000000000013'
\set sessionID '3a1a0000-0000-0000-0000-000000000014'
\set submission1ID '3a1a0000-0000-0000-0000-000000000015'
\set submission2ID '3a1a0000-0000-0000-0000-000000000016'
\set submission3ID '3a1a0000-0000-0000-0000-000000000017'
\set user1ID '3a1a0000-0000-0000-0000-000000000018'
\set user2ID '3a1a0000-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID', jsonb_build_object('username', 'alice-list-event-cfs-submissions'));
select fx_user(:'user2ID', jsonb_build_object('username', 'bob-list-event-cfs-submissions'));
select fx_user(:'reviewer1ID', jsonb_build_object('username', 'reviewer-1'));
select fx_user(:'reviewer2ID', jsonb_build_object('username', 'reviewer-2'));

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
    );

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Event description',
    'published', true
));

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'label1ID', :'eventID', 'track / backend', '#DBEAFE'),
    (:'label2ID', :'eventID', 'track / frontend', '#FEE2E2');

-- Empty event
select fx_event(:'eventEmptyID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Event description',
    'published', true
));

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

-- CFS submission labels
insert into cfs_submission_label (cfs_submission_id, event_cfs_label_id) values
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

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list event submissions
select is(
    list_event_cfs_submissions(:'eventID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
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
                        'event_cfs_label_id', :'label1ID'::uuid,
                        'name', 'track / backend'
                    ),
                    jsonb_build_object(
                        'color', '#FEE2E2',
                        'event_cfs_label_id', :'label2ID'::uuid,
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
                        'event_cfs_label_id', :'label1ID'::uuid,
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
        list_event_cfs_submissions(:'eventID'::uuid, '{"limit": 1, "offset": 1}'::jsonb)::jsonb
        -> 'submissions' -> 0 ->> 'cfs_submission_id'
    )::uuid,
    :'submission1ID'::uuid,
    'Should paginate submissions'
);

-- Should return empty submissions for events without submissions
select is(
    list_event_cfs_submissions(:'eventEmptyID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty submissions for events without submissions'
);

-- Should filter submissions requiring all selected labels
select is(
    list_event_cfs_submissions(
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
                    'event_cfs_label_id', :'label1ID'::uuid,
                    'name', 'track / backend'
                ),
                jsonb_build_object(
                    'color', '#FEE2E2',
                    'event_cfs_label_id', :'label2ID'::uuid,
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

-- Should sort submissions by created date ascending
select is(
    (
        select jsonb_agg(submission->'cfs_submission_id')
        from jsonb_array_elements(
            list_event_cfs_submissions(
                :'eventID'::uuid,
                '{"limit": 10, "offset": 0, "sort": "created-asc"}'::jsonb
            )::jsonb->'submissions'
        ) submission
    ),
    jsonb_build_array(:'submission1ID'::uuid, :'submission2ID'::uuid),
    'Should sort submissions by created date ascending'
);

-- Should sort submissions by ratings count descending
select is(
    (
        select jsonb_agg(submission->'cfs_submission_id')
        from jsonb_array_elements(
            list_event_cfs_submissions(
                :'eventID'::uuid,
                '{"limit": 10, "offset": 0, "sort": "ratings-count-desc"}'::jsonb
            )::jsonb->'submissions'
        ) submission
    ),
    jsonb_build_array(:'submission2ID'::uuid, :'submission1ID'::uuid),
    'Should sort submissions by ratings count descending'
);

-- Should sort submissions by ratings count ascending
select is(
    (
        select jsonb_agg(submission->'cfs_submission_id')
        from jsonb_array_elements(
            list_event_cfs_submissions(
                :'eventID'::uuid,
                '{"limit": 10, "offset": 0, "sort": "ratings-count-asc"}'::jsonb
            )::jsonb->'submissions'
        ) submission
    ),
    jsonb_build_array(:'submission1ID'::uuid, :'submission2ID'::uuid),
    'Should sort submissions by ratings count ascending'
);

-- Should sort stars ascending
select is(
    (
        select jsonb_agg(submission->'cfs_submission_id')
        from jsonb_array_elements(
            list_event_cfs_submissions(
                :'eventID'::uuid,
                '{"limit": 10, "offset": 0, "sort": "stars-asc"}'::jsonb
            )::jsonb->'submissions'
        ) submission
    ),
    jsonb_build_array(:'submission1ID'::uuid, :'submission2ID'::uuid),
    'Should sort stars ascending'
);

-- Should sort stars descending
select is(
    (
        select jsonb_agg(submission->'cfs_submission_id')
        from jsonb_array_elements(
            list_event_cfs_submissions(
                :'eventID'::uuid,
                '{"limit": 10, "offset": 0, "sort": "stars-desc"}'::jsonb
            )::jsonb->'submissions'
        ) submission
    ),
    jsonb_build_array(:'submission2ID'::uuid, :'submission1ID'::uuid),
    'Should sort stars descending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
