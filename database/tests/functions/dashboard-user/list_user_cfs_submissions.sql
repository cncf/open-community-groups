-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a090000-0000-0000-0000-000000000001'
\set eventCategoryID '4a090000-0000-0000-0000-000000000002'
\set eventID '4a090000-0000-0000-0000-000000000003'
\set groupCategoryID '4a090000-0000-0000-0000-000000000004'
\set groupID '4a090000-0000-0000-0000-000000000005'
\set label1ID '4a090000-0000-0000-0000-000000000006'
\set label2ID '4a090000-0000-0000-0000-000000000007'
\set proposal1ID '4a090000-0000-0000-0000-000000000008'
\set proposal2ID '4a090000-0000-0000-0000-000000000009'
\set submission1ID '4a090000-0000-0000-0000-000000000010'
\set submission2ID '4a090000-0000-0000-0000-000000000011'
\set userEmptyID '4a090000-0000-0000-0000-000000000012'
\set userID '4a090000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

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
        :'userID'
    ),
    (
        :'proposal2ID',
        '2024-01-03 00:00:00+00',
        'Talk about Go',
        make_interval(mins => 60),
        'intermediate',
        'Go Intro',
        :'userID'
    );

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'cfs_description', 'CFS open',
    'cfs_enabled', true,
    'cfs_ends_at', current_timestamp + interval '1 day',
    'cfs_starts_at', current_timestamp - interval '1 day',
    'ends_at', current_timestamp + interval '8 days',
    'published', true,
    'starts_at', current_timestamp + interval '7 days'
));

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'label1ID', :'eventID', 'track / backend', '#DBEAFE'),
    (:'label2ID', :'eventID', 'track / frontend', '#FEE2E2');

-- CFS submissions
insert into cfs_submission (
    cfs_submission_id,
    created_at,
    event_id,
    session_proposal_id,
    status_id,
    action_required_message
) values
    (
        :'submission1ID',
        '2024-01-04 00:00:00+00',
        :'eventID',
        :'proposal1ID',
        'information-requested',
        'Need more info'
    ),
    (
        :'submission2ID',
        '2024-01-03 00:00:00+00',
        :'eventID',
        :'proposal2ID',
        'not-reviewed',
        null
    );

-- CFS submission labels
insert into cfs_submission_label (cfs_submission_id, event_cfs_label_id) values
    (:'submission1ID', :'label1ID'),
    (:'submission2ID', :'label1ID'),
    (:'submission2ID', :'label2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list user submissions
select is(
    list_user_cfs_submissions(:'userID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions',
        jsonb_build_array(
            jsonb_build_object(
                'action_required_message',
                'Need more info',
                'cfs_submission_id',
                :'submission1ID'::uuid,
                'created_at',
                extract(epoch from '2024-01-04 00:00:00+00'::timestamptz)::bigint,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
                'labels',
                jsonb_build_array(
                    jsonb_build_object(
                        'color',
                        '#DBEAFE',
                        'event_cfs_label_id',
                        :'label1ID'::uuid,
                        'name',
                        'track / backend'
                    )
                ),
                'linked_session_id',
                null,
                'session_proposal',
                jsonb_build_object(
                    'description',
                    'Talk about Rust',
                    'duration_minutes',
                    45,
                    'session_proposal_id',
                    :'proposal1ID'::uuid,
                    'session_proposal_level_id',
                    'beginner',
                    'session_proposal_level_name',
                    'Beginner',
                    'title',
                    'Rust Intro'
                ),
                'status_id',
                'information-requested',
                'status_name',
                'Information requested',
                'updated_at',
                null
            ),
            jsonb_build_object(
                'action_required_message',
                null,
                'cfs_submission_id',
                :'submission2ID'::uuid,
                'created_at',
                extract(epoch from '2024-01-03 00:00:00+00'::timestamptz)::bigint,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
                'labels',
                jsonb_build_array(
                    jsonb_build_object(
                        'color',
                        '#DBEAFE',
                        'event_cfs_label_id',
                        :'label1ID'::uuid,
                        'name',
                        'track / backend'
                    ),
                    jsonb_build_object(
                        'color',
                        '#FEE2E2',
                        'event_cfs_label_id',
                        :'label2ID'::uuid,
                        'name',
                        'track / frontend'
                    )
                ),
                'linked_session_id',
                null,
                'session_proposal',
                jsonb_build_object(
                    'description',
                    'Talk about Go',
                    'duration_minutes',
                    60,
                    'session_proposal_id',
                    :'proposal2ID'::uuid,
                    'session_proposal_level_id',
                    'intermediate',
                    'session_proposal_level_name',
                    'Intermediate',
                    'title',
                    'Go Intro'
                ),
                'status_id',
                'not-reviewed',
                'status_name',
                'Not reviewed',
                'updated_at',
                null
            )
        ),
        'total',
        2
    ),
    'Should list user submissions'
);

-- Should paginate submissions
select is(
    list_user_cfs_submissions(:'userID'::uuid, '{"limit": 1, "offset": 1}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions',
        jsonb_build_array(
            jsonb_build_object(
                'action_required_message',
                null,
                'cfs_submission_id',
                :'submission2ID'::uuid,
                'created_at',
                extract(epoch from '2024-01-03 00:00:00+00'::timestamptz)::bigint,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
                'labels',
                jsonb_build_array(
                    jsonb_build_object(
                        'color',
                        '#DBEAFE',
                        'event_cfs_label_id',
                        :'label1ID'::uuid,
                        'name',
                        'track / backend'
                    ),
                    jsonb_build_object(
                        'color',
                        '#FEE2E2',
                        'event_cfs_label_id',
                        :'label2ID'::uuid,
                        'name',
                        'track / frontend'
                    )
                ),
                'linked_session_id',
                null,
                'session_proposal',
                jsonb_build_object(
                    'description',
                    'Talk about Go',
                    'duration_minutes',
                    60,
                    'session_proposal_id',
                    :'proposal2ID'::uuid,
                    'session_proposal_level_id',
                    'intermediate',
                    'session_proposal_level_name',
                    'Intermediate',
                    'title',
                    'Go Intro'
                ),
                'status_id',
                'not-reviewed',
                'status_name',
                'Not reviewed',
                'updated_at',
                null
            )
        ),
        'total',
        2
    ),
    'Should paginate submissions'
);

-- Should return empty submissions for users without submissions
select is(
    list_user_cfs_submissions(:'userEmptyID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty submissions for users without submissions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
